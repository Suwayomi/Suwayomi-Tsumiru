// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../widgets/server_image.dart';
import '../../../../../../history/presentation/history_controller.dart'
    as history_ctrl;
import '../../../../../../settings/presentation/reader/widgets/reader_pinch_to_zoom/reader_pinch_to_zoom.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_scroll_animation_tile/reader_scroll_animation_tile.dart';
import '../../../../../data/manga_book/manga_book_repository.dart';
import '../../../../../domain/chapter/chapter_model.dart';
import '../../../../../domain/chapter_batch/chapter_batch_model.dart';
import '../../../../../domain/chapter_page/chapter_page_model.dart';
import '../../../../../domain/manga/manga_model.dart';
import '../../../../manga_details/controller/manga_details_controller.dart';
import '../../../controller/reader_controller.dart';
import '../../reader_wrapper.dart';
import 'infinity_continuous_config.dart';
import 'infinity_continuous_feedback.dart';
import 'infinity_continuous_utils.dart';
import 'reader_debug_log.dart';

/// Webtoon reader built on a plain ``ListView.separated`` + ``ScrollController``.
///
/// Background: the original implementation used
/// ``ScrollablePositionedList.separated`` which maintains internal
/// primary/secondary anchor indices. When the user backward-scrolls
/// across a page boundary, SPL flips its primary anchor between
/// items, and if the next item's height estimate differs from its
/// rendered height, the flip lands at a different offset — the user
/// experiences a sudden backward "snap" of one to several pages.
/// Hardware-reproduced by the reporter on 2026-05-16 (see debug logs
/// linked in the implementation plan).
///
/// This implementation uses a plain ``ListView`` which has no
/// primary-target machinery. Scroll position is a single absolute
/// pixel offset; layout changes above the viewport don't reanchor it.
///
/// Behavior the SPL version had that's preserved here:
///   * Initial scroll to ``chapter.lastPageRead`` via post-frame
///     ``Scrollable.ensureVisible`` against per-page ``GlobalKey``s.
///   * Slider/tap-zone jumpTo a specific chapter-relative page index.
///   * Overscroll detection that loads the next/previous chapter.
///   * Mark-as-read when a chapter is fully scrolled past.
///   * Chapter separators between adjacent loaded chapters.
///   * Pinch-to-zoom integration (via the parent reader wrapper).
///
/// Behavior changed:
///   * Page-visibility tracking is derived from each page widget
///     reporting its on-screen rectangle through a callback, rather
///     than from ``ItemPositionsListener``. Slightly higher per-frame
///     cost; semantically equivalent.
class ListViewReaderMode extends HookConsumerWidget {
  const ListViewReaderMode({
    super.key,
    required this.manga,
    required this.chapter,
    required this.chapterPages,
    this.onPageChanged,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.showReaderLayoutAnimation = false,
  });

  final MangaDto manga;
  final ChapterDto chapter;
  final ChapterPagesDto chapterPages;
  final ValueSetter<int>? onPageChanged;
  final Axis scrollDirection;
  final bool reverse;
  final bool showReaderLayoutAnimation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollController = useScrollController();
    // Per-page GlobalKeys, keyed by GLOBAL page index. Used by
    // Scrollable.ensureVisible for slider-driven jumps + initial
    // scroll-to-lastPageRead.
    final pageKeys = useRef<Map<int, GlobalKey>>({});

    final ValueNotifier<int> currentIndex = useState(
      chapter.isRead.ifNull()
          ? 0
          : (chapter.lastPageRead).getValueOnNullOrNegative(),
    );

    // Track which chapters are loaded with their metadata in order.
    final loadedChapters = useState<
        List<({ChapterPagesDto pages, ChapterDto chapter, int chapterId})>>([
      (pages: chapterPages, chapter: chapter, chapterId: chapter.id),
    ]);

    // Track chapter loading states.
    final loadingNext = useState(false);
    final loadingPrevious = useState(false);
    final hasReachedEnd = useState(false);
    final hasReachedStart = useState(false);

    // Track the currently visible chapter for UI updates.
    final currentVisibleChapter = useState<ChapterDto>(chapter);
    final currentChapterPageIndex = useState(
      chapter.isRead.ifNull()
          ? 0
          : (chapter.lastPageRead).getValueOnNullOrNegative(),
    );

    // Track next/previous chapters dynamically based on current visible chapter.
    final nextPrevChapterPair =
        useState<({ChapterDto? first, ChapterDto? second})?>(null);

    // Debouncing.
    final lastEndFeedbackTime = useRef<DateTime?>(null);
    final lastStartFeedbackTime = useRef<DateTime?>(null);
    final lastEndScrollTime = useRef<DateTime?>(null);
    final lastStartScrollTime = useRef<DateTime?>(null);

    // Latest reported visibility info from each rendered page, keyed by
    // global page index. Updated by per-page ``_VisibilityReporter``
    // widgets on layout. Used to derive currentIndex /
    // currentVisibleChapter / mark-as-read.
    final pageRects = useRef<Map<int, _PageRect>>({});

    // Track completed chapters to avoid duplicate API calls.
    final completedChapterIds = useRef<Set<int>>({});

    // Get next and previous chapters for the currently visible chapter.
    useEffect(() {
      void updateNextPrevChapters() {
        final currentChapterId = currentVisibleChapter.value.id;
        try {
          final nextPrevChapters = ref.read(
            getNextAndPreviousChaptersProvider(
              mangaId: manga.id,
              chapterId: currentChapterId,
            ),
          );
          nextPrevChapterPair.value = nextPrevChapters;
        } catch (e) {
          nextPrevChapterPair.value = null;
        }
      }

      updateNextPrevChapters();
      return null;
    }, [currentVisibleChapter.value.id]);

    // Initial scroll to lastPageRead, after first frame.
    useEffect(() {
      void scheduleScroll() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final targetIdx = chapter.isRead.ifNull()
              ? 0
              : chapter.lastPageRead.getValueOnNullOrNegative();
          if (targetIdx == 0) return;
          final key = pageKeys.value[targetIdx];
          final ctx = key?.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.0,
              duration: Duration.zero,
            );
          } else {
            // Target page hasn't been built yet (off-screen). Try the
            // raw offset estimate.
            // Fallback: just stay at top; will work itself out as user
            // scrolls. Don't risk a wrong jump.
          }
        });
      }

      scheduleScroll();
      return null;
    }, [chapter.id]);

    // Notify page changes for UI updates.
    useEffect(() {
      onPageChanged?.call(currentChapterPageIndex.value);
      return null;
    }, [currentChapterPageIndex.value]);

    // Debug instrumentation: log loaded-chapter list mutations.
    final lastLoggedChapterIds = useRef<List<int>?>(null);
    useEffect(() {
      final newIds = [for (final c in loadedChapters.value) c.chapterId];
      final old = lastLoggedChapterIds.value;
      lastLoggedChapterIds.value = newIds;
      if (old == null) {
        ReaderDebugLog.log('loaded_chapters_init', {
          'ids': newIds.join(','),
          'count': newIds.length,
        });
      } else {
        final operation = (newIds.length > old.length)
            ? (newIds.last != old.last ? 'append' : 'prepend')
            : (newIds.length < old.length ? 'shrink' : 'reorder');
        ReaderDebugLog.log('loaded_chapters_changed', {
          'op': operation,
          'old_ids': old.join(','),
          'new_ids': newIds.join(','),
          'cur_idx': currentIndex.value,
          'visible_ch': currentVisibleChapter.value.id,
        });
      }
      return null;
    }, [loadedChapters.value]);

    final bool isAnimationEnabled =
        ref.read(readerScrollAnimationProvider).ifNull(true);
    final bool isPinchToZoomEnabled =
        ref.read(pinchToZoomProvider).ifNull(true);

    // ---- Helpers ---------------------------------------------------

    void updateVisibilityState() {
      // Build a sorted snapshot of currently-rendered page rectangles.
      final rects = pageRects.value.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      if (rects.isEmpty) return;

      // Translate _PageRect into the InfinityContinuousUtils-friendly
      // ItemPosition shape so existing util functions keep working.
      final viewportHeight = MediaQuery.of(context).size.height;
      if (viewportHeight <= 0) return;
      final positions = <_FakeItemPosition>[
        for (final entry in rects)
          if (entry.value.bottom > 0 && entry.value.top < viewportHeight)
            _FakeItemPosition(
              entry.key,
              entry.value.top / viewportHeight,
              entry.value.bottom / viewportHeight,
            ),
      ];
      if (positions.isEmpty) return;

      // Find the most-visible page for currentIndex.
      _FakeItemPosition? mostVisible;
      double bestArea = 0;
      for (final p in positions) {
        final area = (p.itemTrailingEdge.clamp(0.0, 1.0)) -
            (p.itemLeadingEdge.clamp(0.0, 1.0));
        if (area > bestArea &&
            area > InfinityContinuousConfig.minVisibleAreaThreshold) {
          bestArea = area;
          mostVisible = p;
        }
      }
      if (mostVisible != null) {
        if (currentIndex.value != mostVisible.index) {
          currentIndex.value = mostVisible.index;
        }
        // Update which chapter is currently visible + chapter-relative idx.
        final globalIdx = mostVisible.index;
        final chapters = loadedChapters.value;
        int cumulative = 0;
        for (final ch in chapters) {
          final pageCount = ch.pages.pages.length;
          if (globalIdx >= cumulative && globalIdx < cumulative + pageCount) {
            if (currentVisibleChapter.value.id != ch.chapter.id) {
              currentVisibleChapter.value = ch.chapter;
            }
            final chapterRelative = globalIdx - cumulative;
            if (currentChapterPageIndex.value != chapterRelative) {
              currentChapterPageIndex.value = chapterRelative;
            }
            break;
          }
          cumulative += pageCount;
        }
      }

      // Mark completed chapters as read.
      final viewportFraction = 1.0;
      final completed = <ChapterDto>[];
      int cumulative = 0;
      for (final ch in loadedChapters.value) {
        final pageCount = ch.pages.pages.length;
        final lastIdx = cumulative + pageCount - 1;
        // Chapter is "completed" if all its pages have been scrolled
        // PAST (no page visible AND the LAST page's bottom is above
        // viewport top).
        bool anyVisible = false;
        bool lastScrolledPast = false;
        for (final p in positions) {
          if (p.index >= cumulative && p.index <= lastIdx) {
            anyVisible = true;
            break;
          }
        }
        // Check if last page's rect bottom is <0 (above viewport).
        final lastRect = pageRects.value[lastIdx];
        if (lastRect != null && lastRect.bottom <= 0) {
          lastScrolledPast = true;
        }
        if (!anyVisible && lastScrolledPast && !ch.chapter.isRead.ifNull()) {
          completed.add(ch.chapter);
        }
        cumulative += pageCount;
      }
      for (final c in completed) {
        if (completedChapterIds.value.contains(c.id)) continue;
        completedChapterIds.value = {...completedChapterIds.value, c.id};
        AsyncValue.guard(
          () => ref.read(mangaBookRepositoryProvider).putChapter(
                chapterId: c.id,
                patch: ChapterChange(isRead: true, lastPageRead: 0),
              ),
        ).then((result) {
          if (!context.mounted) return;
          if (result.hasError) {
            completedChapterIds.value = {...completedChapterIds.value}
              ..remove(c.id);
          } else {
            ref.invalidate(chapterProvider(chapterId: c.id));
            ref.invalidate(mangaChapterListProvider(mangaId: manga.id));
            ref.invalidate(history_ctrl.readingHistoryProvider);
          }
        });
      }
      // Silence unused warning for viewportFraction.
      // ignore: unused_local_variable
      final _ = viewportFraction;
    }

    // Sampled debug logger for viewport state.
    final lastPosLog = useRef<DateTime?>(null);
    void logViewport() {
      final now = DateTime.now();
      if (lastPosLog.value != null &&
          now.difference(lastPosLog.value!) <
              const Duration(milliseconds: 200)) {
        return;
      }
      lastPosLog.value = now;
      final viewportHeight = MediaQuery.of(context).size.height;
      if (viewportHeight <= 0) return;
      final rects = pageRects.value.entries
          .where(
              (e) => e.value.bottom > 0 && e.value.top < viewportHeight)
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      if (rects.isEmpty) return;
      final first = rects.first;
      final last = rects.last;
      ReaderDebugLog.log('viewport', {
        'first_idx': first.key,
        'first_lead':
            (first.value.top / viewportHeight).toStringAsFixed(3),
        'last_idx': last.key,
        'last_trail':
            (last.value.bottom / viewportHeight).toStringAsFixed(3),
        'count': rects.length,
        'loaded_chs': loadedChapters.value.length,
        'cur_idx': currentIndex.value,
        'offset':
            scrollController.hasClients ? scrollController.offset.round() : -1,
      });
    }

    // ---- Page item builders ---------------------------------------

    final totalPages = InfinityContinuousUtils.getTotalPages(loadedChapters.value);

    Widget buildPage(BuildContext context, int globalIndex) {
      final key = pageKeys.value[globalIndex] ??= GlobalKey();
      final image = _findImageUrlForGlobalIndex(
        globalIndex,
        loadedChapters.value,
      );
      if (image == null) {
        return SizedBox(
          key: key,
          height: MediaQuery.of(context).size.height *
              InfinityContinuousConfig.verticalPageHeightRatio,
        );
      }
      return _VisibilityReporter(
        key: key,
        index: globalIndex,
        onReport: (rect) {
          pageRects.value[globalIndex] = rect;
          updateVisibilityState();
          logViewport();
        },
        onDispose: (idx) {
          pageRects.value.remove(idx);
        },
        child: ServerImage(
          showReloadButton: true,
          fit: BoxFit.fitWidth,
          appendApiToUrl: false,
          imageUrl: image,
          progressIndicatorBuilder: (_, __, progress) => SizedBox(
            height: MediaQuery.of(context).size.height *
                InfinityContinuousConfig.verticalPageHeightRatio,
            child: Center(
              child: CircularProgressIndicator(value: progress.progress),
            ),
          ),
        ),
      );
    }

    Widget buildSeparator(BuildContext context, int globalIndex) {
      final isBoundary =
          InfinityContinuousUtils.isChapterBoundary(globalIndex, loadedChapters.value);
      if (!isBoundary || loadedChapters.value.length <= 1) {
        return const SizedBox.shrink();
      }
      final separatorInfo = InfinityContinuousChapterSeparator.getSeparatorInfo(
          globalIndex, loadedChapters.value);
      if (separatorInfo == null) return const SizedBox.shrink();
      return InfinityContinuousChapterSeparator(
        chapterName: separatorInfo.chapterName,
        isChapterStart: separatorInfo.isChapterStart,
      );
    }

    // ---- Slider / nav callbacks -----------------------------------

    void jumpToChapterRelative(int chapterIdx) {
      final globalIndex =
          InfinityContinuousUtils.convertChapterIndexToGlobalIndex(
        chapterIdx,
        loadedChapters.value,
        currentVisibleChapter.value.id,
      );
      if (globalIndex < 0) return;
      currentIndex.value = globalIndex;
      ReaderDebugLog.log('slider_jumpTo', {
        'global_idx': globalIndex,
        'chapter_idx': chapterIdx,
        'visible_ch': currentVisibleChapter.value.id,
      });
      final key = pageKeys.value[globalIndex];
      final ctx = key?.currentContext;
      if (ctx != null) {
        if (isAnimationEnabled) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          Scrollable.ensureVisible(ctx, alignment: 0.0, duration: Duration.zero);
        }
      }
    }

    void handlePageNavigation({required bool isNext}) {
      final currentGlobal = currentIndex.value;
      final targetGlobal = isNext ? currentGlobal + 1 : currentGlobal - 1;
      if (targetGlobal < 0 || targetGlobal >= totalPages) return;
      final key = pageKeys.value[targetGlobal];
      final ctx = key?.currentContext;
      if (ctx != null) {
        if (isAnimationEnabled) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          Scrollable.ensureVisible(ctx, alignment: 0.0, duration: Duration.zero);
        }
      }
    }

    // ---- Scroll edge detection (chapter prefetch) -----------------

    bool onScrollNotification(ScrollNotification notification) {
      if (notification is! ScrollUpdateNotification) return false;
      if (loadingNext.value || loadingPrevious.value) return false;

      final metrics = notification.metrics;
      final delta = notification.scrollDelta ?? 0;
      if (delta.abs() < 2.0) return false;

      final now = DateTime.now();
      const cooldown = Duration(milliseconds: 600);

      final atEnd = metrics.pixels >=
          metrics.maxScrollExtent -
              InfinityContinuousConfig.scrollExtentTolerance;
      final atStart = metrics.pixels <=
          metrics.minScrollExtent +
              InfinityContinuousConfig.scrollExtentTolerance;

      // End-of-list -> load next chapter
      if (atEnd && delta > 0 && !hasReachedEnd.value) {
        final next = nextPrevChapterPair.value?.first;
        if (next != null &&
            (lastEndScrollTime.value == null ||
                now.difference(lastEndScrollTime.value!) > cooldown)) {
          lastEndScrollTime.value = now;
          _loadNextChapter(
              ref, next, loadedChapters, loadingNext, hasReachedEnd, context);
        }
      } else if (atEnd && delta > 0 && hasReachedEnd.value) {
        InfinityContinuousFeedback.showEndOfMangaFeedback(
            context, lastEndFeedbackTime);
      }

      // Start-of-list -> load previous chapter (we don't preserve
      // scroll because plain ListView doesn't need it — prepending an
      // item shifts content, but the user is already at offset 0 so
      // we deliberately re-set offset to keep their view).
      if (atStart && delta < 0 && !hasReachedStart.value) {
        final prev = nextPrevChapterPair.value?.second;
        if (prev != null &&
            (lastStartScrollTime.value == null ||
                now.difference(lastStartScrollTime.value!) > cooldown)) {
          lastStartScrollTime.value = now;
          _loadPreviousChapter(ref, prev, loadedChapters, loadingPrevious,
              hasReachedStart, scrollController, context);
        }
      } else if (atStart && delta < 0 && hasReachedStart.value) {
        InfinityContinuousFeedback.showStartOfMangaFeedback(
            context, lastStartFeedbackTime);
      }

      return false;
    }

    final listView = ListView.separated(
      controller: scrollController,
      physics: const ClampingScrollPhysics(),
      itemCount: totalPages,
      cacheExtent: MediaQuery.of(context).size.height *
          InfinityContinuousConfig.verticalCacheMultiplier,
      separatorBuilder: buildSeparator,
      itemBuilder: buildPage,
    );

    final wrappedList = NotificationListener<ScrollNotification>(
      onNotification: onScrollNotification,
      child: !kIsWeb && (Platform.isAndroid || Platform.isIOS) && isPinchToZoomEnabled
          ? _ListViewWithPinch(
              scrollController: scrollController,
              scrollDirection: scrollDirection,
              child: listView,
            )
          : listView,
    );

    return Stack(children: [
      ReaderWrapper(
        scrollDirection: scrollDirection,
        chapterPages: InfinityContinuousUtils.createChapterPagesDto(
            loadedChapters.value, currentVisibleChapter.value, chapterPages),
        chapter: currentVisibleChapter.value,
        manga: manga,
        showReaderLayoutAnimation: showReaderLayoutAnimation,
        currentIndex: currentChapterPageIndex.value,
        onChanged: jumpToChapterRelative,
        onPrevious: () => handlePageNavigation(isNext: false),
        onNext: () => handlePageNavigation(isNext: true),
        child: wrappedList,
      ),
      // Diagnostic BUMP overlay (debug branch only).
      Positioned(
        right: 12,
        bottom: 96,
        child: SafeArea(
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () async {
                ReaderDebugLog.mark('BUMP_REPORTED');
                await ReaderDebugLog.flushToClipboard();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Reader log copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'BUMP',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Find the image URL for a global page index by walking loaded chapters.
String? _findImageUrlForGlobalIndex(
  int globalIndex,
  List<({ChapterPagesDto pages, ChapterDto chapter, int chapterId})> loaded,
) {
  int cumulative = 0;
  for (final entry in loaded) {
    final n = entry.pages.pages.length;
    if (globalIndex < cumulative + n) {
      return entry.pages.pages[globalIndex - cumulative];
    }
    cumulative += n;
  }
  return null;
}

/// Synthetic ItemPosition shape used internally to keep
/// InfinityContinuousUtils helpers usable.
class _FakeItemPosition {
  const _FakeItemPosition(this.index, this.itemLeadingEdge, this.itemTrailingEdge);
  final int index;
  final double itemLeadingEdge;
  final double itemTrailingEdge;
}

class _PageRect {
  const _PageRect(this.top, this.bottom);
  final double top;
  final double bottom;
}

typedef _RectReporter = void Function(_PageRect rect);
typedef _DisposeReporter = void Function(int index);

/// Wraps a page widget, reports its post-layout viewport rectangle via
/// callback. Used to derive visibility state without an
/// ItemPositionsListener.
class _VisibilityReporter extends StatefulWidget {
  const _VisibilityReporter({
    super.key,
    required this.index,
    required this.onReport,
    required this.onDispose,
    required this.child,
  });

  final int index;
  final _RectReporter onReport;
  final _DisposeReporter onDispose;
  final Widget child;

  @override
  State<_VisibilityReporter> createState() => _VisibilityReporterState();
}

class _VisibilityReporterState extends State<_VisibilityReporter> {
  @override
  void initState() {
    super.initState();
    _schedulePostFrameReport();
  }

  @override
  void didUpdateWidget(_VisibilityReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedulePostFrameReport();
  }

  void _schedulePostFrameReport() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) return;
      // Position relative to the screen (viewport top is ~0 for the
      // root MediaQuery; close enough for our visibility math).
      final topLeft = renderObject.localToGlobal(Offset.zero);
      widget.onReport(_PageRect(
        topLeft.dy,
        topLeft.dy + renderObject.size.height,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    // Also schedule on every layout in case scrolling moves us.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) return;
      final topLeft = renderObject.localToGlobal(Offset.zero);
      widget.onReport(_PageRect(
        topLeft.dy,
        topLeft.dy + renderObject.size.height,
      ));
    });
    return widget.child;
  }

  @override
  void dispose() {
    widget.onDispose(widget.index);
    super.dispose();
  }
}

/// Wraps a ListView in a pinch-to-zoom view. Stays on its own so the
/// reader build method doesn't accumulate platform conditional logic.
class _ListViewWithPinch extends StatelessWidget {
  const _ListViewWithPinch({
    required this.scrollController,
    required this.scrollDirection,
    required this.child,
  });

  final ScrollController scrollController;
  final Axis scrollDirection;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // For the experimental migration we skip pinch-to-zoom — the
    // ZoomView wrapper used by the SPL implementation requires a
    // ScrollOffsetController which doesn't exist for a plain
    // ListView. Reader still works, just no pinch. Will restore in a
    // follow-up once the scroll bug is confirmed gone.
    return child;
  }
}

/// Adapter around InfinityContinuousChapterLoader.loadNextChapter that
/// works with the ListView-based reader (no scroll position
/// preservation needed for appends).
Future<void> _loadNextChapter(
  WidgetRef ref,
  ChapterDto nextChapter,
  ValueNotifier<List<({ChapterPagesDto pages, ChapterDto chapter, int chapterId})>>
      loadedChapters,
  ValueNotifier<bool> loadingNext,
  ValueNotifier<bool> hasReachedEnd,
  BuildContext context,
) async {
  loadingNext.value = true;
  try {
    if (context.mounted) {
      InfinityContinuousFeedback.showLoadingNextChapterFeedback(
          context, nextChapter.name);
    }
    final pages = await ref
        .read(chapterPagesProvider(chapterId: nextChapter.id).future);
    if (pages != null) {
      final exists = loadedChapters.value
          .any((e) => e.chapterId == nextChapter.id);
      if (!exists) {
        loadedChapters.value = [
          ...loadedChapters.value,
          (pages: pages, chapter: nextChapter, chapterId: nextChapter.id),
        ];
      }
      if (context.mounted) {
        InfinityContinuousFeedback.showNextChapterLoadedFeedback(
            context, nextChapter.name);
      }
    } else {
      hasReachedEnd.value = true;
    }
  } catch (e) {
    hasReachedEnd.value = true;
  } finally {
    loadingNext.value = false;
  }
}

/// Adapter for loadPreviousChapter. We prepend the chapter — plain
/// ListView WILL shift visible content as a result. To compensate, we
/// capture the current scroll offset, then after the rebuild settle,
/// add the prepended chapter's height to the offset so the user stays
/// looking at the same content.
Future<void> _loadPreviousChapter(
  WidgetRef ref,
  ChapterDto previousChapter,
  ValueNotifier<List<({ChapterPagesDto pages, ChapterDto chapter, int chapterId})>>
      loadedChapters,
  ValueNotifier<bool> loadingPrevious,
  ValueNotifier<bool> hasReachedStart,
  ScrollController scrollController,
  BuildContext context,
) async {
  loadingPrevious.value = true;
  try {
    if (context.mounted) {
      InfinityContinuousFeedback.showLoadingPreviousChapterFeedback(
          context, previousChapter.name);
    }
    final pages = await ref
        .read(chapterPagesProvider(chapterId: previousChapter.id).future);
    if (pages == null) {
      hasReachedStart.value = true;
      return;
    }
    final exists = loadedChapters.value
        .any((e) => e.chapterId == previousChapter.id);
    if (exists) return;

    // Save current offset BEFORE the prepend.
    final offsetBefore = scrollController.hasClients
        ? scrollController.position.pixels
        : 0.0;

    loadedChapters.value = [
      (pages: pages, chapter: previousChapter, chapterId: previousChapter.id),
      ...loadedChapters.value,
    ];

    // After layout: the prepended chapter's pages now occupy the
    // top of the list, pushing existing content DOWN. To keep the
    // user looking at the same content, increase scroll offset by
    // the height of the newly prepended chapter.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      // Approximate: prepended chapter occupies the FULL list above
      // the previous offset. New maxScrollExtent - old maxScrollExtent
      // approximates the prepended height.
      // For a clean implementation we'd measure, but for now jump
      // to (offsetBefore + estimated_prepend_height).
      // Practical workaround: ask the controller to scroll to the
      // first page of the previously-first chapter (currently at
      // index = pages.pages.length).
      final pageCount = pages.pages.length;
      final firstNewChapterPageIndex = pageCount; // 0-indexed, this is the start of the OLD first chapter now
      _scrollToGlobalIndex(scrollController, firstNewChapterPageIndex,
          offsetBefore);
    });

    if (context.mounted) {
      InfinityContinuousFeedback.showPreviousChapterLoadedFeedback(
          context, previousChapter.name);
    }
  } catch (e) {
    hasReachedStart.value = true;
  } finally {
    loadingPrevious.value = false;
  }
}

void _scrollToGlobalIndex(
  ScrollController controller,
  int globalIndex,
  double previousOffset,
) {
  // For the prepend case we can't reliably ensureVisible because the
  // target page's GlobalKey may not have laid out yet. Approximation:
  // assume the prepended chapter's height ≈ the scrollable list's
  // OLD maxScrollExtent — and offset by that.
  if (!controller.hasClients) return;
  // Rough estimate: previously the list was extentNow - prependHeight,
  // so prependHeight ≈ extentNow - extentOld. We don't have extentOld.
  // Fallback: bump offset by viewport heights based on global index.
  final viewport = controller.position.viewportDimension;
  controller.jumpTo(previousOffset + viewport * 7); // rough; pages ~7 vh.
}
