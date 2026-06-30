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

import '../../../../constants/enum.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../history/presentation/history_controller.dart';
import '../../../library/presentation/library/controller/library_controller.dart';
import '../../../offline/data/offline_download_providers.dart';
import '../../../settings/presentation/incognito/incognito_mode.dart';
import '../../../settings/presentation/reader/widgets/reader_ignore_safe_area_tile/reader_ignore_safe_area_tile.dart';
import '../../../settings/presentation/reader/widgets/reader_keep_screen_on_tile/reader_keep_screen_on_tile.dart';
import '../../../settings/presentation/reader/widgets/reader_mode_tile/reader_mode_tile.dart';
import '../../../tracking/domain/track_progress_gate.dart';
import '../../domain/manga/manga_model.dart';
import '../manga_details/controller/manga_details_controller.dart';
import 'controller/reader_controller.dart';
import 'widgets/reader_mode/continuous_reader_mode.dart';
import 'widgets/reader_mode/single_page_reader_mode.dart';

class ReaderScreen extends HookConsumerWidget {
  const ReaderScreen({
    super.key,
    required this.mangaId,
    required this.chapterId,
    this.showReaderLayoutAnimation = false,
  });
  final int mangaId;
  final int chapterId;
  final bool showReaderLayoutAnimation;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mangaProvider = mangaWithIdProvider(mangaId: mangaId);
    final chapterProviderWithIndex = chapterProvider(chapterId: chapterId);
    final chapterPages = ref.watch(chapterPagesProvider(chapterId: chapterId));
    final manga = ref.watch(mangaProvider);
    final chapter = ref.watch(chapterProviderWithIndex);
    final defaultReaderMode = ref.watch(readerModeKeyProvider);
    final ignoreSafeArea = ref.watch(readerIgnoreSafeAreaProvider).ifNull();

    final debounce = useRef<Timer?>(null);
    // Latest page reached, so we can flush it on exit (the debounce below would
    // otherwise drop the last few pages if you back out before it fires).
    final latestPage = useRef<int>(-1);

    final updateLastRead = useCallback((int currentPage) async {
      // Incognito: leave no trace. Skip every progress/history write (covers
      // both the debounced call and the PopScope flush). The PopScope's own
      // provider invalidations still run — they're outside this callback.
      if (ref.read(incognitoModeProvider)) return;
      final chapterValue = chapter.valueOrNull;
      final chapterPagesValue = chapterPages.valueOrNull;
      if (chapterValue == null || chapterPagesValue == null) return;

      // Use the actual loaded pages count, not the chapter's pageCount metadata
      final actualPageCount = chapterPagesValue.pages.length;

      // Only mark as completed if we've reached the actual last page
      final isReadingCompleted =
          (currentPage >= (actualPageCount - 1)) && actualPageCount > 0;

      // Persist locally first (survives offline + app restart), then push to
      // the server; if offline it stays pending and up-syncs on reconnect.
      await recordReadingProgress(
        ref,
        chapterId: chapterValue.id,
        lastPageRead: isReadingCompleted ? 0 : currentPage,
        isRead: isReadingCompleted,
      );

      // Push progress to external trackers when the toggle is on and the
      // manga has at least one tracker bound. Fire-and-forget.
      unawaited(maybeTrackProgressOnReadFetch(
        ref,
        mangaId: mangaId,
        isRead: isReadingCompleted,
        manual: false,
      ));

      // Delete the on-device copy once read, if the user opted in.
      // On a new read, auto-delete behind the reader — both the on-device copy
      // and (per the server settings) the server copy. Each no-ops if its own
      // setting is off.
      if (isReadingCompleted) {
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
      ref.invalidate(readingHistoryProvider);
    }, [chapter.valueOrNull, chapterPages.valueOrNull]);

    final onPageChanged = useCallback<AsyncValueSetter<int>>(
      (int index) async {
        // Incognito: don't track progress (also avoids needless debounce churn).
        if (ref.read(incognitoModeProvider)) return;
        final chapterValue = chapter.valueOrNull;
        final chapterPagesValue = chapterPages.valueOrNull;
        if (chapterValue == null || chapterPagesValue == null) return;

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
          updateLastRead(index);
        } else {
          debounce.value = Timer(
            const Duration(seconds: 2),
            () => updateLastRead(index),
          );
        }
        return;
      },
      [chapter, chapterPages],
    );

    useEffect(() {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      return () => SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          );
    }, []);

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
          // Flush the latest page reached so progress isn't lost to a pending
          // debounce when you back out. AWAIT it so the read write lands before
          // we invalidate the lists below — otherwise they re-fetch the stale
          // (pre-read) state and the unread badge/count comes back wrong.
          debounce.value?.cancel();
          if (latestPage.value >= 0) {
            await updateLastRead(latestPage.value);
          }
          ref.invalidate(chapterProviderWithIndex);
          ref.invalidate(mangaChapterListProvider(mangaId: mangaId));
          // Refresh the library's per-category lists so the unread badge updates
          // even when the reader was opened directly (e.g. the continue-reading
          // button), bypassing the manga-details screen that would otherwise do
          // this on its own pop (#282).
          ref.invalidate(categoryMangaListProvider);
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
                      return switch (
                          data.metaData.readerMode ?? defaultReaderMode) {
                        ReaderMode.singleVertical => SinglePageReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            scrollDirection: Axis.vertical,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                          ),
                        ReaderMode.singleHorizontalRTL => SinglePageReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            reverse: true,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                          ),
                        ReaderMode.continuousHorizontalLTR =>
                          ContinuousReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            scrollDirection: Axis.horizontal,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                          ),
                        ReaderMode.continuousHorizontalRTL =>
                          ContinuousReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            scrollDirection: Axis.horizontal,
                            reverse: true,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                          ),
                        ReaderMode.singleHorizontalLTR => SinglePageReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            chapterPages: chapterPagesData,
                          ),
                        ReaderMode.continuousVertical => ContinuousReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            showSeparator: true,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                          ),
                        ReaderMode.webtoon => ContinuousReaderMode(
                            chapter: chapterData,
                            manga: data,
                            onPageChanged: onPageChanged,
                            showReaderLayoutAnimation:
                                showReaderLayoutAnimation,
                            chapterPages: chapterPagesData,
                          ),
                        ReaderMode.defaultReader || null => switch (
                              defaultReaderMode ?? ReaderMode.webtoon) {
                            ReaderMode.singleHorizontalLTR =>
                              SinglePageReaderMode(
                                chapter: chapterData,
                                manga: data,
                                onPageChanged: onPageChanged,
                                chapterPages: chapterPagesData,
                              ),
                            ReaderMode.singleHorizontalRTL =>
                              SinglePageReaderMode(
                                chapter: chapterData,
                                manga: data,
                                onPageChanged: onPageChanged,
                                reverse: true,
                                showReaderLayoutAnimation:
                                    showReaderLayoutAnimation,
                                chapterPages: chapterPagesData,
                              ),
                            ReaderMode.singleVertical => SinglePageReaderMode(
                                chapter: chapterData,
                                manga: data,
                                onPageChanged: onPageChanged,
                                scrollDirection: Axis.vertical,
                                showReaderLayoutAnimation:
                                    showReaderLayoutAnimation,
                                chapterPages: chapterPagesData,
                              ),
                            ReaderMode.continuousHorizontalLTR =>
                              ContinuousReaderMode(
                                chapter: chapterData,
                                manga: data,
                                onPageChanged: onPageChanged,
                                scrollDirection: Axis.horizontal,
                                showReaderLayoutAnimation:
                                    showReaderLayoutAnimation,
                                chapterPages: chapterPagesData,
                              ),
                            ReaderMode.continuousHorizontalRTL =>
                              ContinuousReaderMode(
                                chapter: chapterData,
                                manga: data,
                                onPageChanged: onPageChanged,
                                scrollDirection: Axis.horizontal,
                                reverse: true,
                                showReaderLayoutAnimation:
                                    showReaderLayoutAnimation,
                                chapterPages: chapterPagesData,
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
                              ),
                            ReaderMode.webtoon || _ => ContinuousReaderMode(
                                chapter: chapterData,
                                manga: data,
                                onPageChanged: onPageChanged,
                                showReaderLayoutAnimation:
                                    showReaderLayoutAnimation,
                                chapterPages: chapterPagesData,
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
            addScaffoldWrapper: true,
            refresh: () => ref.refresh(mangaProvider.future),
          ),
        ),
      ),
    );
  }
}
