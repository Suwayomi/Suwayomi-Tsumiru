// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/enum.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../history/presentation/history_controller.dart';
import '../../../../../offline/data/offline_download_providers.dart';
import '../../../../../offline/data/offline_repository.dart';
import '../../../../../settings/presentation/incognito/incognito_mode.dart';
import '../../../../../settings/presentation/reader/widgets/reader_feedback_toasts_tile/reader_feedback_toasts_tile.dart';
import '../../../../../tracking/domain/track_progress_gate.dart';
import '../../../../domain/chapter/chapter_model.dart';
import '../../../../domain/chapter_page/chapter_page_model.dart';
import '../../../../domain/manga/manga_model.dart';
import '../../../manga_details/controller/manga_details_controller.dart';
import '../../controller/reader_controller.dart';
import '../../controller/reader_settings_model.dart';
import '../../utils/reader_initial_page.dart';
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

/// Multi-chapter paged reader (LTR/RTL/vertical, single & double-page).
///
/// The paged counterpart of [MultiChapterContinuousReaderMode]: prev/current/
/// next chapters live in ONE [PagedReaderViewport], so crossing a chapter
/// boundary is a page turn inside the same pager (no `pushReplacement`, no route
/// slide, no per-chapter system-UI toggle). This host owns chapter loading, the
/// per-visible-chapter progress engine, and the idle-gated window swap; the
/// viewport owns the gesture/zoom/snap machinery.
class MultiChapterPagedReaderMode extends HookConsumerWidget {
  const MultiChapterPagedReaderMode({
    super.key,
    required this.manga,
    required this.chapter,
    required this.chapterPages,
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

  /// Accepted for signature parity with the single-chapter reader; this host
  /// owns progress itself (like the webtoon multi-chapter reader) and ignores
  /// it — ReaderScreen's debounce stays inert for this path.
  final ValueSetter<int>? onPageChanged;
  final bool reverse;
  final Axis scrollDirection;
  final bool showReaderLayoutAnimation;
  final ReaderMode? effectiveReaderMode;
  final bool openAtEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool readerToastsEnabled() =>
        ref.read(readerFeedbackToastsProvider).ifNull(true);

    final controller = useMemoized(() => PagedReaderController());
    final settings = ref.watch(readerEffectiveSettingsProvider(manga.id));

    final isHorizontal = scrollDirection == Axis.horizontal;
    final isLandscape = context.width > context.height;
    final wantDouble = isHorizontal &&
        (settings.pageLayout == PageLayout.doublePages ||
            (settings.pageLayout == PageLayout.automatic && isLandscape) ||
            settings.trueDualPageSpread);
    final splitWide = settings.dualPageSplitPaged && isHorizontal;
    final splitInvert = settings.dualPageInvertPaged;
    final reversePair = settings.invertDoublePages != reverse;
    final (pageFit, pageSize) =
        settings.imageScaleType.pagedFit(context.width, context.height);

    final loadedChapters = useState<List<_LoadedChapter>>([
      (pages: chapterPages, chapter: chapter, chapterId: chapter.id),
    ]);
    // Mirror so the once-bound callbacks always read the latest list.
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

    // Direction of the last position change, so a chapter loads only when the
    // user reads TOWARD its edge — never on initial open of a short chapter.
    final lastProgress = useRef<({int id, int rel})?>(null);

    // A window swap staged by a completed load, applied only when the viewport
    // is idle (onIdle) so it never disrupts an in-progress drag/animation. A
    // prepend shifts every index; committing mid-gesture would jump the page.
    final pending = useRef<List<_LoadedChapter>?>(null);

    final nextPrevChapterPair =
        useState<({ChapterDto? first, ChapterDto? second})?>(null);
    useEffect(() {
      try {
        nextPrevChapterPair.value = ref.read(
          getNextAndPreviousChaptersProvider(
            mangaId: manga.id,
            chapterId: currentVisibleChapter.value.id,
          ),
        );
      } catch (_) {
        nextPrevChapterPair.value = null;
      }
      return null;
    }, [currentVisibleChapter.value.id]);

    _LoadedChapter? loadedById(int id) {
      for (final c in loadedRef.value) {
        if (c.chapterId == id) return c;
      }
      return null;
    }

    // --- reading-progress recording (per VISIBLE chapter) ----------------
    // Ported from MultiChapterContinuousReaderMode: record progress for the
    // chapter currently on screen, not the chapter the reader was opened with,
    // through the offline-safe recordReadingProgress path.
    final progressDebounce = useRef<Timer?>(null);
    final latestProgress = useRef<({int chapterId, int rel})?>(null);

    Future<void> writeVisibleProgress(int chapterId, int rel) async {
      if (ref.read(incognitoModeProvider)) return;
      if (chapterId != currentVisibleChapter.value.id) return;
      if (completedChapterIds.value.contains(chapterId)) return;
      final lc = loadedById(chapterId);
      if (lc == null) return;
      if (lc.chapter.isRead.ifNull()) return;
      final pageCount = lc.pages.pages.length;
      final completed = rel >= (pageCount - 1) && pageCount > 0;
      if (!completed &&
          lc.chapter.lastPageRead.getValueOnNullOrNegative() >= rel) {
        return;
      }
      await recordReadingProgress(
        ref,
        chapterId: chapterId,
        lastPageRead: completed ? 0 : rel,
        isRead: completed,
      );
      if (completed && !completedChapterIds.value.contains(chapterId)) {
        completedChapterIds.value = {...completedChapterIds.value, chapterId};
        unawaited(maybeTrackProgressOnReadFetch(ref,
            mangaId: manga.id, isRead: true, manual: false));
        unawaited(maybeDeleteOnReadLocal(ref,
            mangaId: manga.id, readChapterId: chapterId));
        unawaited(maybeDeleteOnReadServer(ref,
            mangaId: manga.id, readChapterId: chapterId));
      }
      ref.invalidate(readingHistoryProvider);
    }

    void scheduleVisibleProgress(int chapterId, int rel) {
      if (ref.read(incognitoModeProvider)) return;
      latestProgress.value = (chapterId: chapterId, rel: rel);
      progressDebounce.value?.cancel();
      final pageCount = loadedById(chapterId)?.pages.pages.length ?? 0;
      if (rel >= (pageCount - 1) && pageCount > 0) {
        unawaited(writeVisibleProgress(chapterId, rel));
      } else {
        progressDebounce.value = Timer(
          const Duration(seconds: 2),
          () => unawaited(writeVisibleProgress(chapterId, rel)),
        );
      }
    }

    useEffect(() {
      scheduleVisibleProgress(
          currentVisibleChapter.value.id, currentChapterPageIndex.value);
      return null;
    }, [currentChapterPageIndex.value, currentVisibleChapter.value.id]);

    // Flush any pending debounced progress on teardown, straight to the on-
    // device catalog (captured at build so it never touches ref while
    // disposing). Ported verbatim from the webtoon reader.
    final offlineEnabledForFlush = ref.read(offlineEnabledProvider);
    final offlineDbForFlush =
        offlineEnabledForFlush ? ref.read(offlineDatabaseProvider) : null;
    final incognitoForFlush = ref.read(incognitoModeProvider);
    useEffect(() {
      return () {
        progressDebounce.value?.cancel();
        final p = latestProgress.value;
        if (p == null) return;
        if (completedChapterIds.value.contains(p.chapterId)) return;
        if (incognitoForFlush || offlineDbForFlush == null) return;
        final lc = loadedById(p.chapterId);
        final pageCount = lc?.pages.pages.length ?? 0;
        final isCompletion = pageCount > 0 && p.rel >= pageCount - 1;
        unawaited(offlineDbForFlush
            .setChapterProgress(p.chapterId,
                lastPageRead: isCompletion ? 0 : p.rel, isRead: isCompletion)
            .catchError((_) {}));
      };
    }, const []);

    // --- chapter loading (staged; committed on viewport idle) ------------

    Future<void> loadNextChapter(ChapterDto next) async {
      if (loadingNext.value || hasReachedEnd.value) return;
      if (loadedRef.value.any((e) => e.chapterId == next.id)) return;
      final staged = pending.value;
      if (staged != null && staged.any((e) => e.chapterId == next.id)) return;
      loadingNext.value = true;
      try {
        if (context.mounted && readerToastsEnabled()) {
          InfinityContinuousFeedback.showLoadingNextChapterFeedback(
              context, next.name);
        }
        final pages =
            await ref.read(chapterPagesProvider(chapterId: next.id).future);
        if (pages == null) {
          hasReachedEnd.value = true;
          return;
        }
        if (loadedRef.value.any((e) => e.chapterId == next.id)) return;
        final base = pending.value ?? loadedRef.value;
        pending.value = [
          ...base,
          (pages: pages, chapter: next, chapterId: next.id),
        ];
        if (context.mounted && readerToastsEnabled()) {
          InfinityContinuousFeedback.showNextChapterLoadedFeedback(
              context, next.name);
        }
      } catch (_) {
        hasReachedEnd.value = true;
      } finally {
        loadingNext.value = false;
      }
    }

    Future<void> loadPreviousChapter(ChapterDto prev) async {
      if (loadingPrevious.value || hasReachedStart.value) return;
      if (loadedRef.value.any((e) => e.chapterId == prev.id)) return;
      final staged = pending.value;
      if (staged != null && staged.any((e) => e.chapterId == prev.id)) return;
      loadingPrevious.value = true;
      try {
        if (context.mounted && readerToastsEnabled()) {
          InfinityContinuousFeedback.showLoadingPreviousChapterFeedback(
              context, prev.name);
        }
        final pages =
            await ref.read(chapterPagesProvider(chapterId: prev.id).future);
        if (pages == null) {
          hasReachedStart.value = true;
          return;
        }
        if (loadedRef.value.any((e) => e.chapterId == prev.id)) return;
        final base = pending.value ?? loadedRef.value;
        pending.value = [
          (pages: pages, chapter: prev, chapterId: prev.id),
          ...base,
        ];
        if (context.mounted && readerToastsEnabled()) {
          InfinityContinuousFeedback.showPreviousChapterLoadedFeedback(
              context, prev.name);
        }
      } catch (_) {
        hasReachedStart.value = true;
      } finally {
        loadingPrevious.value = false;
      }
    }

    // Commit a staged swap while the viewport is idle. Deferred to a microtask
    // so it never runs inside the viewport's own build/re-anchor pass (a
    // setState-during-build). Idempotent: the first run clears `pending`.
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

    // Preload the neighbour the user is reading toward, Komikku-style: within
    // ~5 pages of the visible chapter's far edge and moving that way.
    useEffect(() {
      final visibleId = currentVisibleChapter.value.id;
      final rel = currentChapterPageIndex.value;
      final prev = lastProgress.value;
      lastProgress.value = (id: visibleId, rel: rel);
      final lc = loadedById(visibleId);
      if (lc == null || prev == null) return null; // no direction yet
      final count = lc.pages.pages.length;
      final pair = nextPrevChapterPair.value;

      int posOf(int id) => loadedRef.value.indexWhere((e) => e.chapterId == id);
      final curPos = posOf(visibleId);
      final prevPos = posOf(prev.id);
      final movingForward =
          curPos != prevPos ? curPos > prevPos : rel > prev.rel;
      final movingBackward =
          curPos != prevPos ? curPos < prevPos : rel < prev.rel;

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
    }, [currentChapterPageIndex.value, currentVisibleChapter.value.id]);

    // --- display window --------------------------------------------------

    // Window-edge adjacency: whether an unloaded chapter sits before the first
    // / after the last loaded chapter, so we show a boundary card there.
    final firstLoadedId = loadedChapters.value.first.chapterId;
    final lastLoadedId = loadedChapters.value.last.chapterId;
    final headAdjacency = ref.watch(getNextAndPreviousChaptersProvider(
        mangaId: manga.id, chapterId: firstLoadedId));
    final tailAdjacency = ref.watch(getNextAndPreviousChaptersProvider(
        mangaId: manga.id, chapterId: lastLoadedId));
    final prevChapterExists = headAdjacency?.second != null;
    final nextChapterExists = tailAdjacency?.first != null;

    final window = useMemoized(
      () {
        final windowChapters = <WindowChapter>[
          for (final lc in loadedChapters.value)
            WindowChapter(
              chapterId: lc.chapterId,
              chapterName: lc.chapter.name,
              mapping: buildSpreadMapping(
                pageCount: lc.pages.pages.length,
                doublePages: wantDouble,
                splitWide: splitWide,
                splitInvert: splitInvert,
                isWide: (raw) =>
                    (widePages.value[lc.chapterId] ?? const {}).contains(raw),
              ),
              pages: lc.pages.pages,
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

    // First-build display index for the opening chapter's initial page. Computed
    // once against the first window (opening chapter only).
    final initialDisplayIndex = useMemoized(() {
      final raw = initialChapterPageIndex;
      final d = window.chapterRawToDisplay(chapter.id, raw);
      return d >= 0 ? d : window.firstDisplayOf(chapter.id).clamp(0, 1 << 30);
    }, const []);

    // --- viewport callbacks ----------------------------------------------

    void onChapterPageChanged(int chapterId, int raw) {
      if (currentVisibleChapter.value.id != chapterId) {
        final loaded = loadedRef.value;
        final prevId = currentVisibleChapter.value.id;
        final prevPos = loaded.indexWhere((e) => e.chapterId == prevId);
        final newPos = loaded.indexWhere((e) => e.chapterId == chapterId);
        if (newPos >= 0) {
          currentVisibleChapter.value = loaded[newPos].chapter;
          // Forward boundary crossing: the chapter just left is finished.
          if (prevPos >= 0 && newPos > prevPos) {
            _markChapterRead(
                ref, manga.id, loaded[prevPos].chapter, completedChapterIds,
                context);
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
      if (nextChapterExists) return; // more to load — no end feedback
      if (!context.mounted || !readerToastsEnabled()) return;
      InfinityContinuousFeedback.showEndOfMangaFeedback(
          context, lastEndFeedbackTime);
    }

    void onReachedStartEdge() {
      if (prevChapterExists) return;
      if (!context.mounted || !readerToastsEnabled()) return;
      InfinityContinuousFeedback.showStartOfMangaFeedback(
          context, lastStartFeedbackTime);
    }

    String nameForChapter(int? id) {
      if (id == null) return '';
      for (final lc in loadedRef.value) {
        if (lc.chapterId == id) return lc.chapter.name;
      }
      return '';
    }

    Widget transitionBuilder(TransitionDisplay t) {
      // End card shows the finished chapter; start/interior show the chapter
      // being entered.
      final name = t.isEnd
          ? nameForChapter(t.fromChapterId)
          : nameForChapter(t.toChapterId);
      return _PagedChapterTransition(
        chapterName: name,
        isChapterStart: !t.isEnd,
      );
    }

    // --- ReaderWrapper (fed the VISIBLE-chapter view) --------------------

    final visibleChapterPages = InfinityContinuousUtils.createChapterPagesDto(
        loadedChapters.value, currentVisibleChapter.value, chapterPages);

    List<int>? spreadPageIndexes;
    final visibleWindowChapter =
        window.chapterById(currentVisibleChapter.value.id);
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
      scrollDirection: scrollDirection,
      chapter: currentVisibleChapter.value,
      manga: manga,
      chapterPages: visibleChapterPages,
      currentIndex: currentChapterPageIndex.value,
      onChanged: controller.jumpToRaw,
      showReaderLayoutAnimation: showReaderLayoutAnimation,
      onPrevious: controller.previous,
      onNext: controller.next,
      childHandlesGestures: true,
      handlesOwnChapterNavigation: true,
      isAtFirstBoundary: () => controller.isAtFirst,
      isAtLastBoundary: () => controller.isAtLast,
      spreadPageIndexes: spreadPageIndexes,
      effectiveReaderMode: wrapperReaderMode,
      child: PagedReaderViewport(
        controller: controller,
        window: window,
        initialDisplayIndex: initialDisplayIndex,
        axis: scrollDirection,
        reverse: reverse,
        animateTransitions: settings.animatePageTransitions,
        pageFit: pageFit,
        pageSize: pageSize,
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
        pinchEnabled: settings.pinchToZoom,
        doubleTapToZoom: settings.doubleTapToZoom,
        disableZoomIn: false,
        disableZoomOut: settings.disableZoomOut,
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

/// Mark [chapter] read once and reconcile the relevant providers, tracking
/// already-marked ids so repeated boundary crossings don't re-fire the mutation.
/// Ported from MultiChapterContinuousReaderMode.
void _markChapterRead(
  WidgetRef ref,
  int mangaId,
  ChapterDto chapter,
  ObjectRef<Set<int>> completedChapterIds,
  BuildContext context,
) {
  if (ref.read(incognitoModeProvider)) return;
  if (chapter.isRead.ifNull()) return;
  if (completedChapterIds.value.contains(chapter.id)) return;
  completedChapterIds.value = {...completedChapterIds.value, chapter.id};
  unawaited(recordReadingProgress(
    ref,
    chapterId: chapter.id,
    lastPageRead: 0,
    isRead: true,
  ).then((_) {
    if (!context.mounted) return;
    unawaited(maybeTrackProgressOnReadFetch(
      ref,
      mangaId: mangaId,
      isRead: true,
      manual: false,
    ));
    unawaited(maybeDeleteOnReadLocal(
      ref,
      mangaId: mangaId,
      readChapterId: chapter.id,
    ));
    unawaited(maybeDeleteOnReadServer(
      ref,
      mangaId: mangaId,
      readChapterId: chapter.id,
    ));
  }));
  // Deliberately do NOT invalidate chapterProvider / mangaChapterList here —
  // that would remount the reader mid-read. Read-state is tracked in-session
  // via completedChapterIds; ReaderScreen refreshes on exit (its PopScope).
}

class _PagedChapterTransition extends StatelessWidget {
  const _PagedChapterTransition({
    required this.chapterName,
    required this.isChapterStart,
  });

  final String chapterName;
  final bool isChapterStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: InfinityContinuousChapterSeparator(
          chapterName: chapterName,
          isChapterStart: isChapterStart,
        ),
      ),
    );
  }
}
