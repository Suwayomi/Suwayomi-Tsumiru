// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../constants/db_keys.dart';
import '../../../../constants/enum.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../history/presentation/history_controller.dart';
import '../../../library/presentation/library/controller/library_controller.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../offline/data/offline_download_providers.dart';
import '../../../offline/data/offline_repository.dart';
import '../../../settings/presentation/general/widgets/force_portrait_tile.dart';
import '../../../settings/presentation/incognito/incognito_mode.dart';
import '../../../settings/presentation/reader/widgets/reader_auto_webtoon_mode/reader_auto_webtoon_mode.dart';
import '../../../settings/presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';
import '../../../settings/presentation/reader/widgets/reader_ignore_safe_area_tile/reader_ignore_safe_area_tile.dart';
import '../../../settings/presentation/reader/widgets/reader_keep_screen_on_tile/reader_keep_screen_on_tile.dart';
import '../../../settings/presentation/reader/widgets/reader_mode_tile/reader_mode_tile.dart';
import '../../../settings/presentation/reader/widgets/reader_orientation/reader_orientation.dart';
import '../../../tracking/domain/track_progress_gate.dart';
import '../../data/manga_book/manga_book_repository.dart';
import '../../domain/manga/manga_model.dart';
import '../manga_details/controller/manga_details_controller.dart';
import 'controller/auto_webtoon.dart';
import 'controller/display_cutout.dart';
import 'controller/reader_controller.dart';
import 'widgets/chrome/reader_chrome.dart';
import 'widgets/reader_mode/continuous_reader_mode.dart';
import 'widgets/reader_mode/multichapter_paged_reader_mode.dart';

class ReaderScreen extends HookConsumerWidget {
  const ReaderScreen({
    super.key,
    required this.mangaId,
    required this.chapterId,
    this.showReaderLayoutAnimation = false,
    this.openAtEnd = false,
  });
  final int mangaId;
  final int chapterId;
  final bool showReaderLayoutAnimation;
  final bool openAtEnd;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mangaProvider = mangaWithIdProvider(mangaId: mangaId);
    final chapterProviderWithIndex = chapterProvider(chapterId: chapterId);
    final chapterPages = ref.watch(chapterPagesProvider(chapterId: chapterId));
    final manga = ref.watch(mangaProvider);
    final chapter = ref.watch(chapterProviderWithIndex);
    final defaultReaderMode = ref.watch(readerModeKeyProvider);
    final ignoreSafeArea = ref.watch(readerIgnoreSafeAreaProvider).ifNull();
    final providerContainer = ProviderScope.containerOf(context, listen: false);
    final incognitoMode = ref.watch(incognitoModeProvider);
    final offlineEnabled = ref.watch(offlineEnabledProvider);
    final offlineDatabase =
        offlineEnabled ? ref.watch(offlineDatabaseProvider) : null;
    final mangaBookRepository = ref.watch(mangaBookRepositoryProvider);

    // Auto reading mode: a Default-mode series opens in the reader its type
    // implies (webtoon scroll for manhwa/webtoon, right-to-left paged for
    // manga) THIS session; never written to meta. Null when auto-detect is off,
    // the series has an explicit per-series mode, or the type carries no
    // opinion — in which case the per-series/global default takes over below.
    final mangaData = manga.valueOrNull;
    final autoReaderMode = (ref.watch(autoWebtoonModeProvider).ifNull(true) &&
            mangaData != null &&
            (mangaData.metaData.readerMode ?? ReaderMode.defaultReader) ==
                ReaderMode.defaultReader)
        ? autoReaderModeFor(
            genres: mangaData.genre,
            sourceName: mangaData.source?.name,
          )
        : null;
    final toast = ref.watch(toastProvider);
    // Resolve the l10n string in build (safe); the effect runs during hook-init
    // where an inherited-widget lookup (context.l10n) throws _debugIsInitHook.
    final autoWebtoonSnack = context.l10n.autoWebtoonSnack;
    useEffect(() {
      if (autoReaderMode == ReaderMode.webtoon) {
        toast?.show(autoWebtoonSnack, withMicrotask: true);
      }
      return null;
    }, [autoReaderMode]);

    final debounce = useRef<Timer?>(null);
    // Latest page reached, so we can flush it on exit (the debounce below would
    // otherwise drop the last few pages if you back out before it fires).
    final latestPage = useRef<int>(-1);
    // The first onPageChanged is the on-mount restore, not a page turn.
    // Counting it as reading would mark a chapter opened at its last page read.
    final initialEmitConsumed = useRef<bool>(false);
    // Set once a flush has run, so the unmount cleanup doesn't re-flush after a
    // PopScope pop already did.
    final didFlush = useRef<bool>(false);

    final updateLastRead = useCallback((int currentPage) async {
      // Incognito: leave no trace. Skip every progress/history write (covers
      // both the debounced call and the PopScope flush). The PopScope's own
      // provider invalidations still run — they're outside this callback.
      if (incognitoMode) return;
      final chapterValue = chapter.valueOrNull;
      final chapterPagesValue = chapterPages.valueOrNull;
      if (chapterValue == null || chapterPagesValue == null) return;

      // Use the actual loaded pages count, not the chapter's pageCount metadata
      final actualPageCount = chapterPagesValue.pages.length;

      // Only mark as completed if we've reached the actual last page
      final isReadingCompleted =
          (currentPage >= (actualPageCount - 1)) && actualPageCount > 0;

      if (isReadingCompleted && context.mounted) {
        unawaited(maybeTrackProgressOnReadFetch(
          ref,
          mangaId: mangaId,
          isRead: true,
          manual: false,
        ));
      }

      // Persist locally first (survives offline + app restart), then push to
      // the server; if offline it stays pending and up-syncs on reconnect.
      await recordReadingProgressWithDependencies(
        offlineEnabled: offlineEnabled,
        offlineDatabase: offlineDatabase,
        repository: mangaBookRepository,
        chapterId: chapterValue.id,
        lastPageRead: isReadingCompleted ? 0 : currentPage,
        isRead: isReadingCompleted,
      );

      // Delete the on-device copy once read, if the user opted in.
      // On a new read, auto-delete behind the reader — both the on-device copy
      // and (per the server settings) the server copy. Each no-ops if its own
      // setting is off.
      if (isReadingCompleted && context.mounted) {
        unawaited(maybeDeleteOnReadLocal(
          ref,
          mangaId: mangaId,
          readChapterId: chapterValue.id,
        ));
        unawaited(maybeDeleteOnReadServer(
          ref,
          mangaId: mangaId,
          readChapterId: chapterValue.id,
        ));
      }

      // Invalidate history to refresh the reading progress
      providerContainer.invalidate(readingHistoryProvider);
    }, [
      chapter.valueOrNull,
      chapterPages.valueOrNull,
      incognitoMode,
      offlineEnabled,
      offlineDatabase,
      mangaBookRepository,
      providerContainer,
    ]);

    final onPageChanged = useCallback<AsyncValueSetter<int>>(
      (int index) async {
        // Incognito: don't track progress (also avoids needless debounce churn).
        if (ref.read(incognitoModeProvider)) return;
        final chapterValue = chapter.valueOrNull;
        final chapterPagesValue = chapterPages.valueOrNull;
        if (chapterValue == null || chapterPagesValue == null) return;

        // Consume the initial restore emit — don't record or complete off it.
        if (!initialEmitConsumed.value) {
          initialEmitConsumed.value = true;
          return;
        }

        // Skip if chapter is already read or if we're going backwards
        if ((chapterValue.isRead).ifNull() ||
            (chapterValue.lastPageRead).getValueOnNullOrNegative() >= index) {
          return;
        }

        latestPage.value = index;
        final finalDebounce = debounce.value;
        if ((finalDebounce?.isActive).ifNull()) {
          finalDebounce?.cancel();
        }

        // Use actual loaded pages count instead of chapter metadata
        final actualPageCount = chapterPagesValue.pages.length;

        if (index >= (actualPageCount - 1) && actualPageCount > 0) {
          unawaited(updateLastRead(index));
        } else {
          debounce.value = Timer(
            const Duration(seconds: 2),
            () {
              if (!context.mounted) return;
              unawaited(updateLastRead(index));
            },
          );
        }
        return;
      },
      [chapter, chapterPages, updateLastRead],
    );

    // Hold the latest updateLastRead so the []-deps unmount cleanup below flushes
    // with current chapter data, not the stale callback captured at first build.
    final updateRef = useRef(updateLastRead);
    updateRef.value = updateLastRead;
    useEffect(() {
      return () {
        debounce.value?.cancel();
        // Chapter-skip uses pushReplacement (no PopScope pop), so flush the
        // pending page here or it's lost. Skip if the pop path already did.
        if (!didFlush.value && latestPage.value >= 0) {
          unawaited(updateRef.value(latestPage.value));
        }
      };
    }, []);

    useEffect(() {
      // Fullscreen OFF keeps the OS bars for the whole session (read once at
      // mount; ReaderChrome handles live changes on chrome transitions).
      final fullscreen = ref.read(readerFullscreenProvider) ??
          DBKeys.readerFullscreen.initial as bool;
      SystemChrome.setEnabledSystemUIMode(
        hiddenChromeUiMode(fullscreen: fullscreen),
      );
      // Don't restore the OS bars on dispose: a chapter change is a
      // pushReplacement (old screen disposes as the new one mounts), so
      // restoring here flashes the system bars mid-transition. They're restored
      // on a real exit in the pop handler below instead.
      return null;
    }, []);

    // Draw reader content into the display cutout (notch/punch-hole) when opted
    // in; restore the default window mode on exit. Android-only native attr.
    final underCutout = ref.watch(drawUnderCutoutProvider) ??
        DBKeys.drawUnderCutout.initial as bool;
    useEffect(() {
      setDrawUnderCutout(underCutout);
      return () => setDrawUnderCutout(false);
    }, [underCutout]);

    // Rotation lock: applied once the per-series ?? global value resolves
    // (null until the manga loads, Default never touches the platform).
    // Companion to the immersive effect above — same lifecycle, different
    // platform surface, so the two can't race.
    final readerOrientation = mangaData == null
        ? null
        : mangaData.metaData.readerOrientation ??
            ref.watch(readerOrientationKeyProvider) ??
            ReaderOrientation.defaultRotation;
    useEffect(() {
      final lock = readerOrientation?.deviceOrientations;
      if (lock == null) return null;
      SystemChrome.setPreferredOrientations(lock);
      // Restore the app-wide state on exit — that's portrait-locked when the
      // global "Lock to portrait" toggle is on, fully unlocked otherwise.
      final forcePortrait = ref.read(forcePortraitProvider).ifNull();
      return () => applyForcePortrait(forcePortrait);
    }, [readerOrientation]);

    // Keep the screen awake while reading when the user opted in. The cleanup
    // only exists when we actually enabled (returning null when off), so leaving
    // the reader — or flipping the toggle off mid-read — releases the wakelock
    // and we never disable one we didn't take. Calls are fire-and-forget and
    // their errors ignored, so a platform hiccup (e.g. no foreground activity
    // during a transition) can never crash the reader.
    final keepScreenOn = ref.watch(keepScreenOnProvider).ifNull(true);
    useEffect(() {
      if (!keepScreenOn) return null;
      WakelockPlus.enable().ignore();
      return () => WakelockPlus.disable().ignore();
    }, [keepScreenOn]);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          // Leaving the reader for real — bring the OS bars back (kept hidden
          // across chapter transitions by dropping the dispose-time restore).
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          );
          // Flush the latest page reached so progress isn't lost to a pending
          // debounce when you back out. AWAIT it so the read write lands before
          // we invalidate the lists below — otherwise they re-fetch the stale
          // (pre-read) state and the unread badge/count comes back wrong.
          debounce.value?.cancel();
          try {
            if (latestPage.value >= 0) {
              didFlush.value = true;
              await updateLastRead(latestPage.value);
            }
          } finally {
            providerContainer.invalidate(chapterProviderWithIndex);
            providerContainer
                .invalidate(mangaChapterListProvider(mangaId: mangaId));
            // Refresh the library's per-category lists so the unread badge updates
            // even when the reader was opened directly (e.g. the continue-reading
            // button), bypassing the manga-details screen that would otherwise do
            // this on its own pop (#282).
            providerContainer.invalidate(libraryMangaListProvider);
            providerContainer.invalidate(categoryMangaListProvider);
          }
        }
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SafeArea(
          top: !ignoreSafeArea,
          bottom: !ignoreSafeArea,
          left: !ignoreSafeArea,
          right: !ignoreSafeArea,
          child: manga.showUiWhenData(
            context,
            (data) {
              if (data == null) return const SizedBox.shrink();
              return chapter.showUiWhenData(
                context,
                (chapterData) {
                  if (chapterData == null) return const SizedBox.shrink();
                  return chapterPages.showUiWhenData(
                    context,
                    (chapterPagesData) {
                      if (chapterPagesData == null) {
                        return const SizedBox.shrink();
                      }
                      return switch (autoReaderMode ??
                          data.metaData.readerMode ??
                          defaultReaderMode) {
                        ReaderMode.singleVertical => MultiChapterPagedReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            scrollDirection: Axis.vertical,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                            openAtEnd: openAtEnd,
                          ),
                        ReaderMode.singleHorizontalRTL ||
                        ReaderMode.continuousHorizontalRTL =>
                          MultiChapterPagedReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            reverse: true,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                            openAtEnd: openAtEnd,
                          ),
                        ReaderMode.singleHorizontalLTR ||
                        ReaderMode.continuousHorizontalLTR =>
                          MultiChapterPagedReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            chapterPages: chapterPagesData,
                            openAtEnd: openAtEnd,
                          ),
                        ReaderMode.continuousVertical => ContinuousReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            showSeparator: true,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                            openAtEnd: openAtEnd,
                          ),
                        ReaderMode.webtoon => ContinuousReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                            openAtEnd: openAtEnd,
                          ),
                        ReaderMode.defaultReader || null => switch (
                              defaultReaderMode ?? ReaderMode.webtoon) {
                            ReaderMode.singleHorizontalLTR ||
                            ReaderMode.continuousHorizontalLTR =>
                              MultiChapterPagedReaderMode(
                                chapter: chapterData,
                                manga: data,
                                onPageChanged: onPageChanged,
                                chapterPages: chapterPagesData,
                                openAtEnd: openAtEnd,
                              ),
                            ReaderMode.singleHorizontalRTL ||
                            ReaderMode.continuousHorizontalRTL =>
                              MultiChapterPagedReaderMode(
                                chapter: chapterData,
                                manga: data,
                                onPageChanged: onPageChanged,
                                reverse: true,
                                showReaderLayoutAnimation:
                                    showReaderLayoutAnimation,
                                chapterPages: chapterPagesData,
                                openAtEnd: openAtEnd,
                              ),
                            ReaderMode.singleVertical => MultiChapterPagedReaderMode(
                                chapter: chapterData,
                                manga: data,
                                onPageChanged: onPageChanged,
                                scrollDirection: Axis.vertical,
                                showReaderLayoutAnimation:
                                    showReaderLayoutAnimation,
                                chapterPages: chapterPagesData,
                                openAtEnd: openAtEnd,
                              ),
                            ReaderMode.continuousVertical =>
                              ContinuousReaderMode(
                                chapter: chapterData,
                                manga: data,
                                onPageChanged: onPageChanged,
                                showSeparator: true,
                                showReaderLayoutAnimation:
                                    showReaderLayoutAnimation,
                                chapterPages: chapterPagesData,
                                openAtEnd: openAtEnd,
                              ),
                            ReaderMode.webtoon || _ => ContinuousReaderMode(
                                chapter: chapterData,
                                manga: data,
                                onPageChanged: onPageChanged,
                                showReaderLayoutAnimation:
                                    showReaderLayoutAnimation,
                                chapterPages: chapterPagesData,
                                openAtEnd: openAtEnd,
                              ),
                          }
                      };
                    },
                  );
                },
                refresh: () => ref.refresh(chapterProviderWithIndex.future),
                addScaffoldWrapper: true,
              );
            },
            refresh: () => ref.refresh(mangaProvider.future),
            addScaffoldWrapper: true,
          ),
        ),
      ),
    );
  }
}
