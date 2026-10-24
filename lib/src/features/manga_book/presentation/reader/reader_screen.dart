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
import '../../../../widgets/emoticons.dart';
import '../../../history/presentation/history_controller.dart';
import '../../../library/presentation/library/controller/library_controller.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../offline/data/offline_download_providers.dart';
import '../../../settings/presentation/general/widgets/force_portrait_tile.dart';
import '../../../settings/presentation/incognito/incognito_mode.dart';
import '../../../settings/presentation/reader/widgets/reader_auto_webtoon_mode/reader_auto_webtoon_mode.dart';
import '../../../settings/presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';
import '../../../settings/presentation/reader/widgets/reader_ignore_safe_area_tile/reader_ignore_safe_area_tile.dart';
import '../../../settings/presentation/reader/widgets/reader_keep_screen_on_tile/reader_keep_screen_on_tile.dart';
import '../../../settings/presentation/reader/widgets/reader_mode_tile/reader_mode_tile.dart';
import '../../../settings/presentation/reader/widgets/reader_orientation/reader_orientation.dart';
import '../../../tracking/domain/track_progress_gate.dart';
import '../../domain/chapter/chapter_model.dart';
import '../../domain/chapter_page/chapter_page_model.dart';
import '../../domain/manga/manga_model.dart';
import '../manga_details/controller/manga_details_controller.dart';
import '../manga_details/controller/scanlator_dedup.dart';
import 'controller/auto_webtoon.dart';
import 'controller/display_cutout.dart';
import 'controller/reader_controller.dart';
import 'utils/download_ahead.dart';
import 'utils/flush_progress_on_lifecycle.dart';
import 'utils/reader_progress_queue.dart';
import 'widgets/chrome/reader_chrome.dart';
import 'widgets/reader_mode/infinity_continuous/multichapter_continuous_reader_mode.dart';
import 'widgets/reader_mode/multichapter_paged_reader_mode.dart';

class ReaderScreen extends HookConsumerWidget {
  const ReaderScreen({
    super.key,
    required this.mangaId,
    required this.chapterId,
    this.readerScanlatorGroup,
    this.showReaderLayoutAnimation = false,
    this.openAtEnd = false,
  });
  final int mangaId;
  final int chapterId;
  final String? readerScanlatorGroup;
  final bool showReaderLayoutAnimation;
  final bool openAtEnd;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    watchDownloadAhead(ref);
    final mangaProvider = mangaWithIdProvider(mangaId: mangaId);
    final chapterProviderWithIndex = chapterProvider(chapterId: chapterId);
    ref.watch(localKoSyncProgressProvider(chapterId: chapterId));
    final chapterPages = ref.watch(chapterPagesProvider(chapterId: chapterId));
    final manga = ref.watch(mangaProvider);
    final chapter = ref.watch(chapterProviderWithIndex);
    final defaultReaderMode = ref.watch(readerModeKeyProvider);
    final ignoreSafeArea = ref.watch(readerIgnoreSafeAreaProvider).ifNull();
    final providerContainer = ProviderScope.containerOf(context, listen: false);
    final incognitoMode = ref.watch(incognitoModeProvider);

    // Pin opening data for this screen lifetime; dependency reloads must not remount the reader.
    final pinnedChapter = _usePinned(chapter.value, chapterId);
    final pinnedChapterPages = _usePinned(chapterPages.value, chapterId);

    // Pin auto-detection inputs so a metadata reload cannot switch viewer engines mid-read.
    final mangaData = manga.value;
    final autoSource = _usePinned(mangaData, mangaId);
    final autoReaderMode = mangaData == null || autoSource == null
        ? null
        : sessionAutoReaderMode(
            enabled: ref.watch(autoWebtoonModeProvider).ifNull(true),
            seriesMode: mangaData.metaData.readerMode,
            genres: autoSource.genre,
            sourceName: autoSource.source?.name,
          );
    final toast = ref.watch(toastProvider);
    // Resolve l10n during build; inherited-widget lookup is invalid during hook initialization.
    final autoWebtoonSnack = context.l10n.autoWebtoonSnack;
    useEffect(() {
      if (autoReaderMode == ReaderMode.webtoon) {
        toast?.show(autoWebtoonSnack, withMicrotask: true);
      }
      return null;
    }, [autoReaderMode]);

    final debounce = useRef<Timer?>(null);
    // Keep the latest page for an exit flush before the debounce fires.
    final latestPage = useRef<int>(-1);
    final progressQueue = ref
        .read(readerProgressQueuesProvider)
        .putIfAbsent(chapterId, ReaderProgressQueue.new);
    final progressGeneration = useRef(progressQueue.generation);
    // The initial emit restores position; counting it as reading can complete a chapter on open.
    final initialEmitConsumed = useRef<bool>(false);
    // Set once a flush has run, so the unmount cleanup doesn't re-flush after a
    // PopScope pop already did.
    final didFlush = useRef<bool>(false);

    final updateLastRead = useCallback((int currentPage) async {
      // Incognito suppresses progress/history writes while exit invalidations still run.
      if (incognitoMode ||
          progressQueue.syncing ||
          progressGeneration.value != progressQueue.generation) {
        return;
      }
      final chapterValue = pinnedChapter;
      final chapterPagesValue = pinnedChapterPages;
      if (chapterValue == null || chapterPagesValue == null) return;

      final actualPageCount = chapterPagesValue.pages.length;

      final isReadingCompleted =
          (currentPage >= (actualPageCount - 1)) && actualPageCount > 0;

      if (isReadingCompleted && context.mounted) {
        unawaited(
          maybeTrackProgressOnReadFetch(
            ref.read,
            mangaId: mangaId,
            isRead: true,
            manual: false,
          ),
        );
      }

      // Persist locally before pushing so offline progress survives restart and syncs later.
      final progressResult = await recordReadingProgress(
        ref,
        mangaId: mangaId,
        chapterId: chapterValue.id,
        lastPageRead: currentPage,
        isRead: isReadingCompleted,
        generation: progressGeneration.value,
      );
      // Online-only users have no pending retry row, so surface failed pushes.
      if (progressResult.hasError && context.mounted) {
        toast?.showError(context.l10n.errorSomethingWentWrong);
      }

      // Await the delete enqueue so the pop-time flush includes chapters completed on exit.
      if (isReadingCompleted && context.mounted) {
        await noteChapterFinishedInReader(
          ref,
          mangaId: mangaId,
          chapterId: chapterValue.id,
        );
      }

      // Defer history invalidation because this callback may resume during build.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => providerContainer.invalidate(readingHistoryProvider),
      );
    }, [pinnedChapter, pinnedChapterPages, incognitoMode, providerContainer]);

    final onPageChanged = useCallback<AsyncValueSetter<int>>((int index) async {
      // Incognito: don't track progress (also avoids needless debounce churn).
      if (ref.read(incognitoModeProvider)) return;
      final chapterValue = pinnedChapter;
      final chapterPagesValue = pinnedChapterPages;
      if (chapterValue == null || chapterPagesValue == null) return;

      // Consume the initial restore emit — don't record or complete off it.
      if (!initialEmitConsumed.value) {
        initialEmitConsumed.value = true;
        return;
      }

      unawaited(
        downloadAhead(
          ref,
          mangaId,
          chapterValue.id,
          index,
          readerScanlatorGroup: readerScanlatorGroup,
        ).catchError((Object error) {
          debugPrint('$error');
        }),
      );

      if ((chapterValue.user.isRead).ifNull() ||
          (chapterValue.user.lastPageRead).getValueOnNullOrNegative() >=
              index) {
        return;
      }

      if (progressQueue.syncing) return;
      progressGeneration.value = progressQueue.generation;
      latestPage.value = index;
      final finalDebounce = debounce.value;
      if ((finalDebounce?.isActive).ifNull()) {
        finalDebounce?.cancel();
      }

      final actualPageCount = chapterPagesValue.pages.length;

      if (index >= (actualPageCount - 1) && actualPageCount > 0) {
        unawaited(updateLastRead(index));
      } else {
        debounce.value = Timer(const Duration(seconds: 2), () {
          if (!context.mounted) return;
          unawaited(updateLastRead(index));
        });
      }
      return;
    }, [pinnedChapter, pinnedChapterPages, updateLastRead]);

    // The unmount callback must read the latest chapter data, not its first-build closure.
    final updateRef = useRef(updateLastRead);
    updateRef.value = updateLastRead;
    useEffect(() {
      return () {
        debounce.value?.cancel();
        // Chapter changes use pushReplacement without a pop callback; flush pending progress on teardown.
        if (!didFlush.value && latestPage.value >= 0) {
          unawaited(updateRef.value(latestPage.value));
        }
      };
    }, []);

    // Desktop window close may skip pop/dispose; flush on background and exit too.
    useFlushProgressOnAppLifecycle(() async {
      debounce.value?.cancel();
      if (latestPage.value >= 0) {
        await updateRef.value(latestPage.value);
      }
    });

    useEffect(() {
      final fullscreen =
          ref.read(readerFullscreenProvider) ??
          DBKeys.readerFullscreen.initial as bool;
      SystemChrome.setEnabledSystemUIMode(
        hiddenChromeUiMode(fullscreen: fullscreen),
      );
      // Restore OS bars only on real exit; chapter pushReplacement mounts a new reader during disposal.
      return null;
    }, []);

    final underCutout =
        ref.watch(drawUnderCutoutProvider) ??
        DBKeys.drawUnderCutout.initial as bool;
    useEffect(() {
      setDrawUnderCutout(underCutout);
      return () => setDrawUnderCutout(false);
    }, [underCutout]);

    // Apply rotation once the per-series/global setting resolves; Default leaves the platform unchanged.
    final readerOrientation = mangaData == null
        ? null
        : mangaData.metaData.readerOrientation ??
              ref.watch(readerOrientationKeyProvider) ??
              ReaderOrientation.defaultRotation;
    useEffect(() {
      final lock = readerOrientation?.deviceOrientations;
      if (lock == null) return null;
      SystemChrome.setPreferredOrientations(lock);
      final forcePortrait = ref.read(forcePortraitProvider).ifNull();
      return () => applyForcePortrait(forcePortrait);
    }, [readerOrientation]);

    // Release only a wakelock acquired by this reader; ignore platform transition errors.
    final keepScreenOn = ref.watch(keepScreenOnProvider).ifNull(true);
    useEffect(() {
      if (!keepScreenOn) return null;
      WakelockPlus.enable().ignore();
      return () => WakelockPlus.disable().ignore();
    }, [keepScreenOn]);

    final chapterView = pinnedChapter == null
        ? chapter
        : AsyncData<ChapterDto?>(pinnedChapter);
    final chapterPagesView = pinnedChapterPages == null
        ? chapterPages
        : AsyncData<ChapterPagesDto?>(pinnedChapterPages);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          );
          // Await the progress flush before invalidating lists so they refetch the saved read state.
          debounce.value?.cancel();
          try {
            if (latestPage.value >= 0) {
              didFlush.value = true;
              await updateLastRead(latestPage.value);
            }
          } finally {
            // Drain read deletes on reader exit through the container; writes may outlive the route ref.
            unawaited(flushPendingReadDeletes(providerContainer));
            // Re-reconcile with the normal (not +1) deleteWhileReading slots
            // so the boundary buffer from the last chapter boundary is released.
            unawaited(reconcileMangaContainer(providerContainer, mangaId));
            // Defer post-write invalidation past the pop build phase.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              providerContainer.invalidate(chapterProviderWithIndex);
              providerContainer.invalidate(
                mangaChapterListProvider(mangaId: mangaId),
              );
              providerContainer.invalidate(libraryMangaListProvider);
              providerContainer.invalidate(categoryMangaListProvider);
            });
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
          // Keep manga data visible during reloads while allowing live reading-mode changes.
          child: manga.showUiWhenData(
            context,
            (data) {
              if (data == null) return const SizedBox.shrink();
              return chapterView.showUiWhenData(
                context,
                (chapterData) {
                  if (chapterData == null) return const SizedBox.shrink();
                  return chapterPagesView.showUiWhenData(
                    context,
                    (chapterPagesData) {
                      if (chapterPagesData == null) {
                        return const SizedBox.shrink();
                      }
                      // Empty chapters never mount the reader toolbar, so this view
                      // needs its own back button.
                      if (chapterPagesData.pages.isEmpty) {
                        return Scaffold(
                          appBar: AppBar(),
                          body: Emoticons(
                            title: context.l10n.readerNoPages,
                            subTitle: context.l10n.readerNoPagesSubtitle,
                          ),
                        );
                      }
                      return switch (autoReaderMode ??
                          data.metaData.readerMode ??
                          defaultReaderMode) {
                        ReaderMode.singleVertical =>
                          MultiChapterPagedReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            scrollDirection: Axis.vertical,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                            openAtEnd: openAtEnd,
                            readerScanlatorGroup:
                                readerScanlatorGroup ??
                                scanlatorGroupOf(chapterData),
                          ),
                        ReaderMode.singleHorizontalRTL =>
                          MultiChapterPagedReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            reverse: true,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                            openAtEnd: openAtEnd,
                            readerScanlatorGroup:
                                readerScanlatorGroup ??
                                scanlatorGroupOf(chapterData),
                          ),
                        ReaderMode.singleHorizontalLTR =>
                          MultiChapterPagedReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            chapterPages: chapterPagesData,
                            openAtEnd: openAtEnd,
                            readerScanlatorGroup:
                                readerScanlatorGroup ??
                                scanlatorGroupOf(chapterData),
                          ),
                        ReaderMode.continuousHorizontalRTL =>
                          MultiChapterContinuousReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            scrollDirection: Axis.horizontal,
                            reverse: true,
                            effectiveReaderMode:
                                ReaderMode.continuousHorizontalRTL,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                            openAtEnd: openAtEnd,
                            readerScanlatorGroup:
                                readerScanlatorGroup ??
                                scanlatorGroupOf(chapterData),
                          ),
                        ReaderMode.continuousHorizontalLTR =>
                          MultiChapterContinuousReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            scrollDirection: Axis.horizontal,
                            effectiveReaderMode:
                                ReaderMode.continuousHorizontalLTR,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                            openAtEnd: openAtEnd,
                            readerScanlatorGroup:
                                readerScanlatorGroup ??
                                scanlatorGroupOf(chapterData),
                          ),
                        ReaderMode.continuousVertical =>
                          MultiChapterContinuousReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            effectiveReaderMode: ReaderMode.continuousVertical,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                            openAtEnd: openAtEnd,
                            readerScanlatorGroup:
                                readerScanlatorGroup ??
                                scanlatorGroupOf(chapterData),
                          ),
                        ReaderMode.webtoon => MultiChapterContinuousReaderMode(
                          chapter: chapterData,
                          manga: data,
                          onPageChanged: onPageChanged,
                          showReaderLayoutAnimation: showReaderLayoutAnimation,
                          chapterPages: chapterPagesData,
                          openAtEnd: openAtEnd,
                          readerScanlatorGroup:
                              readerScanlatorGroup ??
                              scanlatorGroupOf(chapterData),
                        ),
                        ReaderMode.defaultReader ||
                        null => switch (defaultReaderMode ??
                            ReaderMode.singleHorizontalRTL) {
                          ReaderMode.singleHorizontalLTR =>
                            MultiChapterPagedReaderMode(
                              chapter: chapterData,
                              manga: data,
                              onPageChanged: onPageChanged,
                              chapterPages: chapterPagesData,
                              openAtEnd: openAtEnd,
                              readerScanlatorGroup:
                                  readerScanlatorGroup ??
                                  scanlatorGroupOf(chapterData),
                            ),
                          ReaderMode.singleHorizontalRTL =>
                            MultiChapterPagedReaderMode(
                              chapter: chapterData,
                              manga: data,
                              onPageChanged: onPageChanged,
                              reverse: true,
                              showReaderLayoutAnimation:
                                  showReaderLayoutAnimation,
                              chapterPages: chapterPagesData,
                              openAtEnd: openAtEnd,
                              readerScanlatorGroup:
                                  readerScanlatorGroup ??
                                  scanlatorGroupOf(chapterData),
                            ),
                          ReaderMode.continuousHorizontalLTR =>
                            MultiChapterContinuousReaderMode(
                              chapter: chapterData,
                              manga: data,
                              onPageChanged: onPageChanged,
                              scrollDirection: Axis.horizontal,
                              effectiveReaderMode:
                                  ReaderMode.continuousHorizontalLTR,
                              showReaderLayoutAnimation:
                                  showReaderLayoutAnimation,
                              chapterPages: chapterPagesData,
                              openAtEnd: openAtEnd,
                              readerScanlatorGroup:
                                  readerScanlatorGroup ??
                                  scanlatorGroupOf(chapterData),
                            ),
                          ReaderMode.continuousHorizontalRTL =>
                            MultiChapterContinuousReaderMode(
                              chapter: chapterData,
                              manga: data,
                              onPageChanged: onPageChanged,
                              scrollDirection: Axis.horizontal,
                              reverse: true,
                              effectiveReaderMode:
                                  ReaderMode.continuousHorizontalRTL,
                              showReaderLayoutAnimation:
                                  showReaderLayoutAnimation,
                              chapterPages: chapterPagesData,
                              openAtEnd: openAtEnd,
                              readerScanlatorGroup:
                                  readerScanlatorGroup ??
                                  scanlatorGroupOf(chapterData),
                            ),
                          ReaderMode.singleVertical =>
                            MultiChapterPagedReaderMode(
                              chapter: chapterData,
                              manga: data,
                              onPageChanged: onPageChanged,
                              scrollDirection: Axis.vertical,
                              showReaderLayoutAnimation:
                                  showReaderLayoutAnimation,
                              chapterPages: chapterPagesData,
                              openAtEnd: openAtEnd,
                              readerScanlatorGroup:
                                  readerScanlatorGroup ??
                                  scanlatorGroupOf(chapterData),
                            ),
                          ReaderMode.continuousVertical =>
                            MultiChapterContinuousReaderMode(
                              chapter: chapterData,
                              manga: data,
                              onPageChanged: onPageChanged,
                              effectiveReaderMode:
                                  ReaderMode.continuousVertical,
                              showReaderLayoutAnimation:
                                  showReaderLayoutAnimation,
                              chapterPages: chapterPagesData,
                              openAtEnd: openAtEnd,
                              readerScanlatorGroup:
                                  readerScanlatorGroup ??
                                  scanlatorGroupOf(chapterData),
                            ),
                          ReaderMode.webtoon ||
                          _ => MultiChapterContinuousReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                            openAtEnd: openAtEnd,
                            readerScanlatorGroup:
                                readerScanlatorGroup ??
                                scanlatorGroupOf(chapterData),
                          ),
                        },
                      };
                    },
                    refresh: () => ref.refresh(
                      chapterPagesProvider(chapterId: chapterId).future,
                    ),
                    addScaffoldWrapper:
                        chapterPagesView.hasError &&
                        !chapterPagesView.isLoading,
                  );
                },
                refresh: () => ref.refresh(chapterProviderWithIndex.future),
                addScaffoldWrapper: true,
              );
            },
            refresh: () => ref.refresh(mangaProvider.future),
            skipLoadingOnReload: true,
            addScaffoldWrapper: true,
          ),
        ),
      ),
    );
  }
}

T? _usePinned<T extends Object>(T? value, int key) {
  final pinned = useRef<({int key, T value})?>(null);
  final current = pinned.value;
  if (current != null && current.key == key) return current.value;
  if (value == null) return null;
  pinned.value = (key: key, value: value);
  return value;
}
