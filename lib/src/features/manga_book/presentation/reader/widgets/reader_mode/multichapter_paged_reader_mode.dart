// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../history/presentation/history_controller.dart';
import '../../../../../offline/data/offline_download_providers.dart';
import '../../../../../offline/data/offline_repository.dart';
import '../../../../../settings/presentation/incognito/incognito_mode.dart';
import '../../../../../settings/presentation/reader/widgets/reader_feedback_toasts_tile/reader_feedback_toasts_tile.dart';
import '../../../../../settings/presentation/reader/widgets/reader_mouse_scroll_speed_slider/reader_mouse_scroll_speed_slider.dart';
import '../../../../../settings/presentation/reader/widgets/reader_webtoon_prefs/reader_webtoon_prefs.dart';
import '../../../../../tracking/domain/track_progress_gate.dart';
import '../../../../data/manga_book/manga_book_repository.dart';
import '../../../../domain/chapter/chapter_model.dart';
import '../../../../domain/chapter/missing_chapters.dart';
import '../../../../domain/chapter_page/chapter_page_model.dart';
import '../../../../domain/manga/manga_model.dart';
import '../../../manga_details/controller/manga_details_controller.dart';
import '../../../manga_details/controller/scanlator_dedup.dart';
import '../../controller/auto_scroll_controller.dart';
import '../../controller/reader_controller.dart';
import '../../controller/reader_settings_model.dart';
import '../../utils/download_ahead.dart';
import '../../utils/reader_initial_page.dart';
import '../../utils/reader_progress_queue.dart';
import '../reader_wrapper.dart';
import 'infinity_continuous/infinity_continuous_feedback.dart';
import 'infinity_continuous/infinity_continuous_utils.dart';
import 'paged_display_window.dart';
import 'paged_reader_viewport.dart';
import 'paged_spread_mapping.dart';

typedef _LoadedChapter = ({
  ChapterPagesDto pages,
  ChapterDto chapter,
  int chapterId,
});

class MultiChapterPagedReaderMode extends HookConsumerWidget {
  const MultiChapterPagedReaderMode({
    super.key,
    required this.manga,
    required this.chapter,
    required this.chapterPages,
    required this.readerScanlatorGroup,
    this.onPageChanged,
    this.reverse = false,
    this.scrollDirection = Axis.horizontal,
    this.showReaderLayoutAnimation = false,
    this.effectiveReaderMode,
    this.openAtEnd = false,
  });

  final MangaDto manga;
  final ChapterDto chapter;
  final ChapterPagesDto chapterPages;
  final String readerScanlatorGroup;

  /// Ignored: this host records progress itself; ReaderScreen debounce stays inactive.
  final ValueSetter<int>? onPageChanged;
  final bool reverse;
  final Axis scrollDirection;
  final bool showReaderLayoutAnimation;
  final ReaderMode? effectiveReaderMode;
  final bool openAtEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    watchDownloadAhead(ref);
    bool readerToastsEnabled() =>
        ref.read(readerFeedbackToastsProvider).ifNull(true);

    // Defer feedback outside hook initialization, where inherited l10n lookups are invalid.
    void deferFeedback(VoidCallback show) {
      if (!readerToastsEnabled()) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        try {
          show();
        } catch (_) {}
      });
    }

    final controller = useMemoized(() => PagedReaderController());
    final settings = ref.watch(readerEffectiveSettingsProvider(manga.id));

    final autoAdvanceActive = ref.watch(autoScrollActiveProvider);
    final autoAdvanceInterval =
        ref.watch(autoAdvanceIntervalSecondsProvider) ??
        DBKeys.autoAdvanceIntervalSeconds.initial as int;
    useEffect(() {
      if (!autoAdvanceActive) return null;
      final timer = Timer.periodic(Duration(seconds: autoAdvanceInterval), (_) {
        if (controller.isAtLast) {
          ref.read(autoScrollActiveProvider.notifier).stop();
          return;
        }
        controller.next();
      });
      return timer.cancel;
    }, [autoAdvanceActive, autoAdvanceInterval]);

    // Stop auto-advance in background so it cannot turn pages and write progress unseen.
    useEffect(() {
      final listener = AppLifecycleListener(
        onHide: () => ref.read(autoScrollActiveProvider.notifier).stop(),
        onPause: () => ref.read(autoScrollActiveProvider.notifier).stop(),
      );
      return listener.dispose;
    }, const []);

    final isHorizontal = scrollDirection == Axis.horizontal;
    final isLandscape = context.width > context.height;
    // Explicit page layout wins; landscape spread only augments Automatic.
    final wantDouble =
        isHorizontal &&
        switch (settings.pageLayout) {
          PageLayout.doublePages => true,
          PageLayout.singlePage => false,
          PageLayout.automatic => isLandscape || settings.trueDualPageSpread,
        };
    final splitWide = settings.dualPageSplitPaged && isHorizontal;
    final splitInvert = settings.dualPageInvertPaged;
    final reversePair = settings.invertDoublePages != reverse;
    final (pageFit, pageSize) = settings.imageScaleType.pagedFit(
      context.width,
      context.height,
    );

    final loadedChapters = useState<List<_LoadedChapter>>([
      (pages: chapterPages, chapter: chapter, chapterId: chapter.id),
    ]);
    final loadedRef = useRef<List<_LoadedChapter>>(loadedChapters.value);
    loadedRef.value = loadedChapters.value;

    // Per-chapter wide (landscape) pages, discovered as images resolve. Keyed by
    // chapterId so two chapters can each have a wide page 0.
    final widePages = useState<Map<int, Set<int>>>(const {});

    final currentVisibleChapter = useState<ChapterDto>(chapter);
    final initialChapterPageIndex = readerInitialPageIndex(
      chapter: chapter,
      chapterPages: chapterPages,
      openAtEnd: openAtEnd,
    );
    final currentChapterPageIndex = useState<int>(initialChapterPageIndex);

    final loadingNext = useState(false);
    final loadingPrevious = useState(false);
    final hasReachedEnd = useState(false);
    final hasReachedStart = useState(false);
    final lastEndFeedbackTime = useRef<DateTime?>(null);
    final lastStartFeedbackTime = useRef<DateTime?>(null);
    final completedChapterIds = useRef<Set<int>>({});

    final sessionChapterIds = useRef<Set<int>>({});
    final sessionNotifier = ref.read(sessionReadChaptersProvider.notifier);
    final incognitoRef = useRef(ref.watch(incognitoModeProvider));
    incognitoRef.value = ref.watch(incognitoModeProvider);
    useEffect(() {
      var active = true;
      void doRecord(int id) {
        if (!active || incognitoRef.value) return;
        if (!sessionChapterIds.value.contains(id)) {
          sessionChapterIds.value = {...sessionChapterIds.value, id};
          // The container may be disposed before this microtask; ignore that teardown race.
          try {
            sessionNotifier.record(id);
          } catch (_) {
          }
        }
      }

      // Defer build-time provider writes to a microtask, which does not need another scheduled frame.
      Future.microtask(() => doRecord(currentVisibleChapter.value.id));
      void onChanged() => doRecord(currentVisibleChapter.value.id);
      currentVisibleChapter.addListener(onChanged);
      return () {
        active = false;
        currentVisibleChapter.removeListener(onChanged);
        // Disposal may occur during build; defer and tolerate an already-disposed container.
        Future.microtask(() {
          try {
            sessionNotifier.discard(sessionChapterIds.value);
          } catch (_) {
          }
        });
      };
    }, const []);

    // Load neighbours only when reading toward an edge, never on the initial short-chapter view.
    final lastProgress = useRef<({int id, int rel})?>(null);

    // Commit staged window swaps only while idle; prepending mid-gesture would shift page indices.
    final pending = useRef<List<_LoadedChapter>?>(null);

    // Watch the loading chapter list and mirror it for the once-bound preload effect.
    final nextPrevChapterPair =
        useRef<({ChapterDto? first, ChapterDto? second})?>(null);
    nextPrevChapterPair.value = ref.watch(
      getNextAndPreviousChaptersProvider(
        mangaId: manga.id,
        chapterId: currentVisibleChapter.value.id,
        readerScanlatorGroup: readerScanlatorGroup,
      ),
    );

    _LoadedChapter? loadedById(int id) {
      for (final c in loadedRef.value) {
        if (c.chapterId == id) return c;
      }
      return null;
    }

    final progressDebounce = useRef<Timer?>(null);
    final latestProgress = useRef<({int chapterId, int rel, int generation})?>(
      null,
    );
    final allChaptersForFlush = useRef<List<ChapterDto>?>(null);
    allChaptersForFlush.value = ref
        .watch(mangaChapterListProvider(mangaId: manga.id))
        .value;

    ReaderProgressQueue progressQueue(int id) => ref
        .read(readerProgressQueuesProvider)
        .putIfAbsent(id, ReaderProgressQueue.new);

    Future<void> writeVisibleProgress(
      int chapterId,
      int rel,
      int generation,
    ) async {
      if (progressQueue(chapterId).generation != generation ||
          progressQueue(chapterId).syncing) {
        return;
      }
      if (ref.read(incognitoModeProvider)) return;
      if (chapterId != currentVisibleChapter.value.id) return;
      if (completedChapterIds.value.contains(chapterId)) return;
      final lc = loadedById(chapterId);
      if (lc == null) return;
      if (lc.chapter.user.isRead.ifNull()) return;
      final pageCount = lc.pages.pages.length;
      final completed = rel >= (pageCount - 1) && pageCount > 0;
      if (!completed &&
          lc.chapter.user.lastPageRead.getValueOnNullOrNegative() >= rel) {
        return;
      }
      final progressResult = await recordReadingProgress(
        ref,
        mangaId: manga.id,
        chapterId: chapterId,
        lastPageRead: rel,
        isRead: completed,
        generation: generation,
      );
      if (!context.mounted ||
          progressQueue(chapterId).generation != generation) {
        return;
      }
      // Surface failed pushes for online-only users because they have no dirty row to retry.
      if (progressResult.hasError) {
        ref
            .read(toastProvider)
            ?.showError(context.l10n.errorSomethingWentWrong);
      }
      if (completed && !completedChapterIds.value.contains(chapterId)) {
        completedChapterIds.value = {...completedChapterIds.value, chapterId};
        unawaited(
          maybeTrackProgressOnReadFetch(
            ref.read,
            mangaId: manga.id,
            isRead: true,
            manual: false,
          ),
        );
        unawaited(
          noteChapterFinishedInReader(
            ref,
            mangaId: manga.id,
            chapterId: chapterId,
          ),
        );
      }
      // Defer invalidation outside scroll/layout notifications to avoid writes during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) ref.invalidate(readingHistoryProvider);
      });
    }

    void scheduleVisibleProgress(int chapterId, int rel) {
      unawaited(
        downloadAhead(
          ref,
          manga.id,
          chapterId,
          rel,
          readerScanlatorGroup: readerScanlatorGroup,
        ).catchError((Object error) {
          debugPrint('$error');
        }),
      );

      if (ref.read(incognitoModeProvider)) return;
      final queue = progressQueue(chapterId);
      if (queue.syncing) return;
      final generation = queue.generation;
      latestProgress.value = (
        chapterId: chapterId,
        rel: rel,
        generation: generation,
      );
      progressDebounce.value?.cancel();
      final pageCount = loadedById(chapterId)?.pages.pages.length ?? 0;
      if (rel >= (pageCount - 1) && pageCount > 0) {
        unawaited(writeVisibleProgress(chapterId, rel, generation));
      } else {
        progressDebounce.value = Timer(
          const Duration(seconds: 2),
          () => unawaited(writeVisibleProgress(chapterId, rel, generation)),
        );
      }
    }

    // Skip the restore emit so opening at the last page cannot complete the chapter.
    final initialProgressConsumed = useRef<bool>(false);
    useEffect(() {
      if (!initialProgressConsumed.value) {
        initialProgressConsumed.value = true;
        return null;
      }
      scheduleVisibleProgress(
        currentVisibleChapter.value.id,
        currentChapterPageIndex.value,
      );
      return null;
    }, [currentChapterPageIndex.value, currentVisibleChapter.value.id]);

    // Capture the DB before teardown and flush pending progress without touching ref.
    final offlineEnabledForFlush = ref.read(offlineEnabledProvider);
    final offlineDbForFlush = offlineEnabledForFlush
        ? ref.read(offlineDatabaseProvider)
        : null;
    final repoForFlush = ref.read(mangaBookRepositoryProvider);
    final progressQueuesForFlush = ref.read(readerProgressQueuesProvider);
    final incognitoForFlush = ref.read(incognitoModeProvider);
    useEffect(() {
      return () {
        progressDebounce.value?.cancel();
        final p = latestProgress.value;
        if (p == null) return;
        final queue = progressQueuesForFlush.putIfAbsent(
          p.chapterId,
          ReaderProgressQueue.new,
        );
        if (queue.syncing || p.generation != queue.generation) return;
        if (completedChapterIds.value.contains(p.chapterId)) return;
        if (incognitoForFlush) return;
        final lc = loadedById(p.chapterId);
        final pageCount = lc?.pages.pages.length ?? 0;
        final isCompletion = pageCount > 0 && p.rel >= pageCount - 1;
        // Fire-and-forget so leaving mid-chapter still saves the spot. A
        // completion carries the same conservative release expansion as the
        // normal reader path; a partial position remains scoped to this row.
        queue.run(() {
          if (p.generation != queue.generation) {
            return Future.value(const AsyncValue<void>.data(null));
          }
          return recordReadingProgressWithDependencies(
          offlineEnabled: offlineEnabledForFlush,
          offlineDatabase: offlineDbForFlush,
          repository: repoForFlush,
          chapterId: p.chapterId,
            lastPageRead: p.rel,
          isRead: isCompletion,
          completionChapterIds: isCompletion
              ? expandIdsForDuplicates(allChaptersForFlush.value, [p.chapterId])
              : null,
          );
        }).ignore();
      };
    }, const []);


    Future<void> loadNextChapter(ChapterDto next) async {
      if (loadingNext.value || hasReachedEnd.value) return;
      if (loadedRef.value.any((e) => e.chapterId == next.id)) return;
      final staged = pending.value;
      if (staged != null && staged.any((e) => e.chapterId == next.id)) return;
      loadingNext.value = true;
      // Hold the autoDispose neighbour provider during fetch; close in finally so retries cannot leak listeners.
      final sub = ref.listenManual(
        chapterPagesProvider(chapterId: next.id),
        (_, _) {},
      );
      try {
        deferFeedback(
          () => InfinityContinuousFeedback.showLoadingNextChapterFeedback(
            context,
            next.name,
          ),
        );
        final ChapterPagesDto? pages;
        try {
          pages = await ref
              .read(chapterPagesProvider(chapterId: next.id).future)
              .timeout(const Duration(seconds: 15));
        } on TimeoutException {
          return;
        }
        if (!context.mounted) return;
        if (pages == null) {
          // An empty fetch is retryable, not the end of the manga; invalidate without latching.
          ref.invalidate(chapterPagesProvider(chapterId: next.id));
          return;
        }
        if (loadedRef.value.any((e) => e.chapterId == next.id)) return;
        final base = pending.value ?? loadedRef.value;
        pending.value = [
          ...base,
          (pages: pages, chapter: next, chapterId: next.id),
        ];
        deferFeedback(
          () => InfinityContinuousFeedback.showNextChapterLoadedFeedback(
            context,
            next.name,
          ),
        );
      } catch (_) {
        // Invalidate transient failures so the next gesture can retry.
        if (context.mounted) {
          ref.invalidate(chapterPagesProvider(chapterId: next.id));
        }
      } finally {
        sub.close();
        if (context.mounted) loadingNext.value = false;
      }
    }

    Future<void> loadPreviousChapter(ChapterDto prev) async {
      if (loadingPrevious.value || hasReachedStart.value) return;
      if (loadedRef.value.any((e) => e.chapterId == prev.id)) return;
      final staged = pending.value;
      if (staged != null && staged.any((e) => e.chapterId == prev.id)) return;
      loadingPrevious.value = true;
      final sub = ref.listenManual(
        chapterPagesProvider(chapterId: prev.id),
        (_, _) {},
      );
      try {
        deferFeedback(
          () => InfinityContinuousFeedback.showLoadingPreviousChapterFeedback(
            context,
            prev.name,
          ),
        );
        final ChapterPagesDto? pages;
        try {
          pages = await ref
              .read(chapterPagesProvider(chapterId: prev.id).future)
              .timeout(const Duration(seconds: 15));
        } on TimeoutException {
          return;
        }
        if (!context.mounted) return;
        if (pages == null) {
          ref.invalidate(chapterPagesProvider(chapterId: prev.id));
          return;
        }
        if (loadedRef.value.any((e) => e.chapterId == prev.id)) return;
        final base = pending.value ?? loadedRef.value;
        pending.value = [
          (pages: pages, chapter: prev, chapterId: prev.id),
          ...base,
        ];
        deferFeedback(
          () => InfinityContinuousFeedback.showPreviousChapterLoadedFeedback(
            context,
            prev.name,
          ),
        );
      } catch (_) {
        if (context.mounted) {
          ref.invalidate(chapterPagesProvider(chapterId: prev.id));
        }
      } finally {
        sub.close();
        if (context.mounted) loadingPrevious.value = false;
      }
    }

    // Commit idle swaps in a microtask to avoid setState during viewport build/re-anchor.
    void commitPendingIfAny() {
      if (pending.value == null) return;
      Future.microtask(() {
        if (!context.mounted) return;
        final p = pending.value;
        if (p == null) return;
        pending.value = null;
        loadedChapters.value = p;
      });
    }

    useEffect(
      () {
        final visibleId = currentVisibleChapter.value.id;
        final rel = currentChapterPageIndex.value;
        final prev = lastProgress.value;
        lastProgress.value = (id: visibleId, rel: rel);
        final lc = loadedById(visibleId);
        if (lc == null || prev == null) return null; // no direction yet
        final count = lc.pages.pages.length;
        final pair = nextPrevChapterPair.value;

        int posOf(int id) =>
            loadedRef.value.indexWhere((e) => e.chapterId == id);
        final curPos = posOf(visibleId);
        final prevPos = posOf(prev.id);
        final movingForward = curPos != prevPos
            ? curPos > prevPos
            : rel > prev.rel;
        final movingBackward = curPos != prevPos
            ? curPos < prevPos
            : rel < prev.rel;

        if (movingForward &&
            loadedRef.value.isNotEmpty &&
            loadedRef.value.last.chapterId == visibleId &&
            rel >= count - 5 &&
            pair?.first != null) {
          unawaited(loadNextChapter(pair!.first!));
        }
        if (movingBackward &&
            loadedRef.value.isNotEmpty &&
            loadedRef.value.first.chapterId == visibleId &&
            rel <= 4 &&
            pair?.second != null) {
          unawaited(loadPreviousChapter(pair!.second!));
        }
        return null;
        // Rerun when neighbour IDs resolve after the initial chapter-list load.
      },
      [
        currentChapterPageIndex.value,
        currentVisibleChapter.value.id,
        nextPrevChapterPair.value?.first?.id,
        nextPrevChapterPair.value?.second?.id,
      ],
    );


    final firstLoadedId = loadedChapters.value.first.chapterId;
    final lastLoadedId = loadedChapters.value.last.chapterId;
    final headAdjacency = ref.watch(
      getNextAndPreviousChaptersProvider(
        mangaId: manga.id,
        chapterId: firstLoadedId,
        readerScanlatorGroup: readerScanlatorGroup,
      ),
    );
    final tailAdjacency = ref.watch(
      getNextAndPreviousChaptersProvider(
        mangaId: manga.id,
        chapterId: lastLoadedId,
        readerScanlatorGroup: readerScanlatorGroup,
      ),
    );
    final prevChapterExists = headAdjacency?.second != null;
    final nextChapterExists = tailAdjacency?.first != null;

    final window = useMemoized(
      () {
        final windowChapters = <WindowChapter>[
          for (var index = 0; index < loadedChapters.value.length; index++)
            WindowChapter(
              chapterId: loadedChapters.value[index].chapterId,
              chapterName: loadedChapters.value[index].chapter.name,
              hasGapBefore:
                  index > 0 &&
                  chapterGap(
                        higher:
                            loadedChapters.value[index].chapter.chapterNumber,
                        lower: loadedChapters
                            .value[index - 1]
                            .chapter
                            .chapterNumber,
                      ) >
                      0,
              mapping: buildSpreadMapping(
                pageCount: loadedChapters.value[index].pages.pages.length,
                doublePages: wantDouble,
                splitWide: splitWide,
                splitInvert: splitInvert,
                isWide: (raw) =>
                    (widePages.value[loadedChapters.value[index].chapterId] ??
                            const {})
                        .contains(raw),
              ),
              pages: loadedChapters.value[index].pages.pages,
            ),
        ];
        return buildPagedDisplayWindow(
          chapters: windowChapters,
          forceTransition: settings.alwaysShowChapterTransition,
          leadingTransition: prevChapterExists,
          trailingTransition: nextChapterExists,
        );
      },
      [
        loadedChapters.value,
        wantDouble,
        splitWide,
        splitInvert,
        widePages.value,
        settings.alwaysShowChapterTransition,
        prevChapterExists,
        nextChapterExists,
      ],
    );

    final initialDisplayIndex = useMemoized(() {
      final raw = initialChapterPageIndex;
      final d = window.chapterRawToDisplay(chapter.id, raw);
      return d >= 0 ? d : window.firstDisplayOf(chapter.id).clamp(0, 1 << 30);
    }, const []);


    void onChapterPageChanged(int chapterId, int raw) {
      if (currentVisibleChapter.value.id != chapterId) {
        final loaded = loadedRef.value;
        final prevId = currentVisibleChapter.value.id;
        final prevPos = loaded.indexWhere((e) => e.chapterId == prevId);
        final newPos = loaded.indexWhere((e) => e.chapterId == chapterId);
        if (newPos >= 0) {
          currentVisibleChapter.value = loaded[newPos].chapter;
          if (prevPos >= 0 && newPos > prevPos) {
            _markChapterRead(
              ref,
              manga.id,
              loaded[prevPos].chapter,
              loaded[prevPos].pages.pages.length,
              completedChapterIds,
              context,
            );
          }
        }
      }
      if (currentChapterPageIndex.value != raw) {
        currentChapterPageIndex.value = raw;
      }
    }

    void onPageWide(int chapterId, int raw, bool wide) {
      if (!wide) return;
      final current = widePages.value[chapterId] ?? const <int>{};
      if (current.contains(raw)) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final now = widePages.value[chapterId] ?? const <int>{};
        if (now.contains(raw)) return;
        widePages.value = {
          ...widePages.value,
          chapterId: {...now, raw},
        };
      });
    }

    void onReachedEndEdge() {
      // Opening at the end or in a one-page chapter gives no forward tick to trigger preloading.
      final nextToLoad = tailAdjacency?.first;
      if (nextToLoad != null && !hasReachedEnd.value) {
        // Idle may precede fetch completion; commit explicitly when the load lands.
        unawaited(
          loadNextChapter(nextToLoad).then((_) {
            if (context.mounted) commitPendingIfAny();
          }),
        );
        return;
      }
      if (nextChapterExists) return; // more to load — no end feedback
      if (!context.mounted || !readerToastsEnabled()) return;
      InfinityContinuousFeedback.showEndOfMangaFeedback(
        context,
        lastEndFeedbackTime,
      );
    }

    void onReachedStartEdge() {
      // Opening at page zero gives no backward preloader tick; trigger the load explicitly.
      final prevToLoad = headAdjacency?.second;
      if (prevToLoad != null && !hasReachedStart.value) {
        unawaited(
          loadPreviousChapter(prevToLoad).then((_) {
            if (context.mounted) commitPendingIfAny();
          }),
        );
        return;
      }
      if (prevChapterExists) return;
      if (!context.mounted || !readerToastsEnabled()) return;
      InfinityContinuousFeedback.showStartOfMangaFeedback(
        context,
        lastStartFeedbackTime,
      );
    }

    String nameForChapter(int? id) {
      if (id == null) return '';
      for (final lc in loadedRef.value) {
        if (lc.chapterId == id) return lc.chapter.name;
      }
      return '';
    }

    Widget transitionBuilder(TransitionDisplay t) {
      final name = t.isEnd
          ? nameForChapter(t.fromChapterId)
          : nameForChapter(t.toChapterId);
      ChapterDto? chapterById(int? id) {
        for (final loaded in loadedChapters.value) {
          if (loaded.chapterId == id) return loaded.chapter;
        }
        return null;
      }

      final from = t.isStart
          ? headAdjacency?.second
          : chapterById(t.fromChapterId);
      final to = t.isEnd ? tailAdjacency?.first : chapterById(t.toChapterId);
      return _PagedChapterTransition(
        chapterName: name,
        isChapterStart: !t.isEnd,
        gapCount: chapterGap(
          higher: to?.chapterNumber,
          lower: from?.chapterNumber,
        ),
      );
    }


    final visibleChapterPages = InfinityContinuousUtils.createChapterPagesDto(
      loadedChapters.value,
      currentVisibleChapter.value,
      chapterPages,
    );

    List<int>? spreadPageIndexes;
    final visibleWindowChapter = window.chapterById(
      currentVisibleChapter.value.id,
    );
    if (visibleWindowChapter != null && !visibleWindowChapter.mapping.isEmpty) {
      final mapping = visibleWindowChapter.mapping;
      final entry =
          mapping.entries[mapping.rawToDisplay(currentChapterPageIndex.value)];
      final second = entry.second;
      if (second != null && second.raw != entry.first.raw) {
        spreadPageIndexes = reversePair
            ? [second.raw, entry.first.raw]
            : [entry.first.raw, second.raw];
      }
    }

    final wrapperReaderMode =
        effectiveReaderMode ?? _pagedReaderMode(scrollDirection, reverse);

    return ReaderWrapper(
      readerScanlatorGroup: readerScanlatorGroup,
      scrollDirection: scrollDirection,
      chapter: currentVisibleChapter.value,
      manga: manga,
      chapterPages: visibleChapterPages,
      currentIndex: currentChapterPageIndex.value,
      onChanged: controller.jumpToRaw,
      showReaderLayoutAnimation: showReaderLayoutAnimation,
      onPrevious: controller.previous,
      onNext: controller.next,
      onToggleAutoScroll: () =>
          ref.read(autoScrollActiveProvider.notifier).toggle(),
      onAutoScrollFaster: () {
        final cur =
            ref.read(autoAdvanceIntervalSecondsProvider) ??
            DBKeys.autoAdvanceIntervalSeconds.initial as int;
        ref
            .read(autoAdvanceIntervalSecondsProvider.notifier)
            .update((cur - 1).clamp(1, 30));
      },
      onAutoScrollSlower: () {
        final cur =
            ref.read(autoAdvanceIntervalSecondsProvider) ??
            DBKeys.autoAdvanceIntervalSeconds.initial as int;
        ref
            .read(autoAdvanceIntervalSecondsProvider.notifier)
            .update((cur + 1).clamp(1, 30));
      },
      childHandlesGestures: true,
      handlesOwnChapterNavigation: true,
      isAtFirstBoundary: () => controller.isAtFirst,
      isAtLastBoundary: () => controller.isAtLast,
      // Bound jumps by the visible chapter page count; controller raw indices are chapter-relative.
      onJumpToFirst: () => controller.jumpToRaw(0),
      onJumpToLast: () =>
          controller.jumpToRaw(visibleChapterPages.pages.length - 1),
      spreadPageIndexes: spreadPageIndexes,
      effectiveReaderMode: wrapperReaderMode,
      child: PagedReaderViewport(
        controller: controller,
        window: window,
        initialDisplayIndex: initialDisplayIndex,
        axis: scrollDirection,
        reverse: reverse,
        animateTransitions:
            settings.animatePageTransitions && !context.reduceMotion,
        pageFit: pageFit,
        pageSize: pageSize,
        pagesAtNaturalSize: settings.imageScaleType.pagesAtNaturalSize,
        mouseScrollSpeed:
            ref.watch(readerMouseScrollSpeedKeyProvider) ??
            DBKeys.readerMouseScrollSpeed.initial,
        centerMargin: settings.centerMarginType,
        rotateWide: settings.rotateWidePages,
        rotateWideInvert: settings.rotateWideInvert,
        reversePair: reversePair,
        cropBorders: settings.cropBorders,
        onPageWide: onPageWide,
        onChapterPageChanged: onChapterPageChanged,
        transitionBuilder: transitionBuilder,
        onIdle: commitPendingIfAny,
        onReachedStartEdge: onReachedStartEdge,
        onReachedEndEdge: onReachedEndEdge,
        pinchEnabled: settings.pagedPinchToZoom,
        doubleTapToZoom: settings.pagedDoubleTapToZoom,
        disableZoomIn: settings.disableZoomIn,
        disableZoomOut: settings.pagedDisableZoomOut,
        navigateToPan: settings.navigateToPan,
      ),
    );
  }
}

ReaderMode _pagedReaderMode(Axis axis, bool reverse) {
  if (axis == Axis.vertical) return ReaderMode.singleVertical;
  return reverse
      ? ReaderMode.singleHorizontalRTL
      : ReaderMode.singleHorizontalLTR;
}

void _markChapterRead(
  WidgetRef ref,
  int mangaId,
  ChapterDto chapter,
  int pageCount,
  ObjectRef<Set<int>> completedChapterIds,
  BuildContext context,
) {
  if (ref.read(incognitoModeProvider)) return;
  if (ref.read(readerProgressQueuesProvider)[chapter.id]?.syncing ?? false) {
    return;
  }
  if (chapter.user.isRead.ifNull()) return;
  if (completedChapterIds.value.contains(chapter.id)) return;
  completedChapterIds.value = {...completedChapterIds.value, chapter.id};
  unawaited(
    recordReadingProgress(
      ref,
      mangaId: mangaId,
      chapterId: chapter.id,
      lastPageRead: (pageCount - 1).clamp(0, 1 << 31),
      isRead: true,
    ).then((progressResult) {
      if (!context.mounted) return;
      // A failed boundary push has no dirty row to retry for online-only users.
      if (progressResult.hasError) {
        ref
            .read(toastProvider)
            ?.showError(context.l10n.errorSomethingWentWrong);
      }
      unawaited(
        maybeTrackProgressOnReadFetch(
          ref.read,
          mangaId: mangaId,
          isRead: true,
          manual: false,
        ),
      );
      unawaited(
        noteChapterFinishedInReader(
          ref,
          mangaId: mangaId,
          chapterId: chapter.id,
        ),
      );
    }),
  );
  // Do not invalidate chapter providers mid-read: remounting resets the reader; refresh on exit.
}

class _PagedChapterTransition extends StatelessWidget {
  const _PagedChapterTransition({
    required this.chapterName,
    required this.isChapterStart,
    required this.gapCount,
  });

  final String chapterName;
  final bool isChapterStart;
  final int gapCount;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: InfinityContinuousChapterSeparator(
          chapterName: chapterName,
          isChapterStart: isChapterStart,
          gapCount: gapCount,
        ),
      ),
    );
  }
}
