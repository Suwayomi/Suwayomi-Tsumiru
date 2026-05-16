// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:zoom_view/zoom_view.dart';

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
/// Why not ``ScrollablePositionedList``: SPL maintains internal
/// primary/secondary anchor indices. When the user back-scrolls across
/// a page boundary, SPL flips its primary anchor between items; if the
/// next item's height estimate differs from its rendered height, the
/// flip lands at a different offset and the user sees a sudden backward
/// "snap" of one or more pages. Reproduced on hardware on 2026-05-16.
/// Plain ``ListView`` has no primary-target machinery: scroll position
/// is one absolute pixel offset and layout changes above the viewport
/// don't reanchor it.
///
/// Multi-chapter prepend (back-loading the previous chapter) needs care
/// even with ListView: inserting items at the top pushes existing
/// content down by the prepended height, which the user would see as a
/// jump. The fix used here is to pick an "anchor" page that is already
/// on screen, store its current viewport-relative top, prepend the
/// chapter, and on the next frame measure where that same widget now
/// sits and re-set the scroll offset so it lands at the same place.
/// Per-page ``GlobalKey``s are stable across prepends because they are
/// keyed by ``(chapterId, pageIdxInChapter)`` rather than by global
/// index, so the anchor widget's RenderBox stays attached through the
/// rebuild and ``localToGlobal`` returns a valid position.
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

    // Keyed by "chapterId:pageIdxInChapter". Stable across prepends —
    // the same widget keeps the same key even when its global index
    // shifts, so ``key.currentContext`` keeps pointing at the same
    // RenderBox.
    final pageKeys = useRef<Map<String, GlobalKey>>({});

    final ValueNotifier<int> currentIndex = useState(
      chapter.isRead.ifNull()
          ? 0
          : (chapter.lastPageRead).getValueOnNullOrNegative(),
    );

    final loadedChapters = useState<
        List<({ChapterPagesDto pages, ChapterDto chapter, int chapterId})>>([
      (pages: chapterPages, chapter: chapter, chapterId: chapter.id),
    ]);

    final loadingNext = useState(false);
    final loadingPrevious = useState(false);
    final hasReachedEnd = useState(false);
    final hasReachedStart = useState(false);

    final currentVisibleChapter = useState<ChapterDto>(chapter);
    final currentChapterPageIndex = useState(
      chapter.isRead.ifNull()
          ? 0
          : (chapter.lastPageRead).getValueOnNullOrNegative(),
    );

    final nextPrevChapterPair =
        useState<({ChapterDto? first, ChapterDto? second})?>(null);

    final lastEndFeedbackTime = useRef<DateTime?>(null);
    final lastStartFeedbackTime = useRef<DateTime?>(null);
    final lastEndScrollTime = useRef<DateTime?>(null);
    final lastStartScrollTime = useRef<DateTime?>(null);

    // Per-page viewport rectangles reported by ``_VisibilityReporter``.
    // Keyed by global index for visibility calculations. Cleared on
    // prepend because global indices shift; new rects arrive next frame.
    final pageRects = useRef<Map<int, _PageRect>>({});

    final completedChapterIds = useRef<Set<int>>({});

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

    // Initial scroll to lastPageRead via per-page GlobalKey.
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final targetIdx = chapter.isRead.ifNull()
            ? 0
            : chapter.lastPageRead.getValueOnNullOrNegative();
        if (targetIdx == 0) return;
        final key = pageKeys.value[_pageKeyId(chapter.id, targetIdx)];
        final ctx = key?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.0,
            duration: Duration.zero,
          );
        }
      });
      return null;
    }, [chapter.id]);

    useEffect(() {
      onPageChanged?.call(currentChapterPageIndex.value);
      return null;
    }, [currentChapterPageIndex.value]);

    // Debug: log loaded-chapter list mutations so a future reproducer
    // log shows the prepend/append timestamps for correlation.
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
        final op = (newIds.length > old.length)
            ? (newIds.last != old.last ? 'append' : 'prepend')
            : (newIds.length < old.length ? 'shrink' : 'reorder');
        ReaderDebugLog.log('loaded_chapters_changed', {
          'op': op,
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

    void updateVisibilityState() {
      final rects = pageRects.value.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      if (rects.isEmpty) return;

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

      _FakeItemPosition? mostVisible;
      double bestArea = 0;
      for (final p in positions) {
        final area = p.itemTrailingEdge.clamp(0.0, 1.0) -
            p.itemLeadingEdge.clamp(0.0, 1.0);
        if (area > bestArea &&
            area > InfinityContinuousConfig.minVisibleAreaThreshold) {
          bestArea = area;
          mostVisible = p;
        }
      }
      if (mostVisible == null) return;

      if (currentIndex.value != mostVisible.index) {
        currentIndex.value = mostVisible.index;
      }
      final globalIdx = mostVisible.index;
      int cumulative = 0;
      for (final ch in loadedChapters.value) {
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

      // Mark fully-scrolled-past chapters as read.
      cumulative = 0;
      final completed = <ChapterDto>[];
      for (final ch in loadedChapters.value) {
        final pageCount = ch.pages.pages.length;
        final lastIdx = cumulative + pageCount - 1;
        bool anyVisible = false;
        for (final p in positions) {
          if (p.index >= cumulative && p.index <= lastIdx) {
            anyVisible = true;
            break;
          }
        }
        final lastRect = pageRects.value[lastIdx];
        final lastScrolledPast = lastRect != null && lastRect.bottom <= 0;
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
    }

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
          .where((e) => e.value.bottom > 0 && e.value.top < viewportHeight)
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      if (rects.isEmpty) return;
      final first = rects.first;
      final last = rects.last;
      ReaderDebugLog.log('viewport', {
        'first_idx': first.key,
        'first_lead': (first.value.top / viewportHeight).toStringAsFixed(3),
        'last_idx': last.key,
        'last_trail': (last.value.bottom / viewportHeight).toStringAsFixed(3),
        'count': rects.length,
        'loaded_chs': loadedChapters.value.length,
        'cur_idx': currentIndex.value,
        'offset':
            scrollController.hasClients ? scrollController.offset.round() : -1,
      });
    }

    final totalPages =
        InfinityContinuousUtils.getTotalPages(loadedChapters.value);

    Widget buildPage(BuildContext context, int globalIndex) {
      final loc = _locateGlobalIndex(globalIndex, loadedChapters.value);
      if (loc == null) {
        return SizedBox(
          height: MediaQuery.of(context).size.height *
              InfinityContinuousConfig.verticalPageHeightRatio,
        );
      }
      final keyId = _pageKeyId(loc.chapterId, loc.pageIdx);
      final key = pageKeys.value[keyId] ??= GlobalKey();
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
          imageUrl: loc.imageUrl,
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
      final isBoundary = InfinityContinuousUtils.isChapterBoundary(
          globalIndex, loadedChapters.value);
      if (!isBoundary || loadedChapters.value.length <= 1) {
        return const SizedBox.shrink();
      }
      final info = InfinityContinuousChapterSeparator.getSeparatorInfo(
          globalIndex, loadedChapters.value);
      if (info == null) return const SizedBox.shrink();
      return InfinityContinuousChapterSeparator(
        chapterName: info.chapterName,
        isChapterStart: info.isChapterStart,
      );
    }

    // Slider debounce — the Slider fires onChanged continuously during
    // a drag; without debounce we'd issue dozens of overlapping scrolls.
    // We keep state updates immediate (so the slider's page-number text
    // tracks the drag) but defer the actual scroll until the user
    // pauses.
    final pendingSliderTimer = useRef<Timer?>(null);

    void scrollToGlobalIndex(int globalIndex,
        {bool animate = true, String? source}) {
      if (!scrollController.hasClients) return;
      if (globalIndex < 0 || globalIndex >= totalPages) return;

      final loc = _locateGlobalIndex(globalIndex, loadedChapters.value);
      if (loc == null) return;
      final keyId = _pageKeyId(loc.chapterId, loc.pageIdx);
      final ctx = pageKeys.value[keyId]?.currentContext;
      final duration = animate
          ? const Duration(milliseconds: 300)
          : Duration.zero;

      // Fast path: target is already built — ensureVisible works.
      if (ctx != null) {
        ReaderDebugLog.log('jump_direct', {
          'source': source ?? 'unknown',
          'global_idx': globalIndex,
          'chapter_id': loc.chapterId,
          'page_idx': loc.pageIdx,
        });
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.0,
          duration: duration,
          curve: Curves.easeOut,
        );
        return;
      }

      // Slow path: target's widget hasn't been built yet (outside the
      // ListView cache window). Estimate the pixel offset and jumpTo,
      // then refine via ensureVisible once the widget has laid out.
      final viewportHeight = MediaQuery.of(context).size.height;
      double avgPageHeight =
          viewportHeight * InfinityContinuousConfig.verticalPageHeightRatio;
      if (pageRects.value.isNotEmpty) {
        double sum = 0;
        int n = 0;
        for (final r in pageRects.value.values) {
          final h = r.bottom - r.top;
          if (h > 0) {
            sum += h;
            n++;
          }
        }
        if (n > 0) avgPageHeight = sum / n;
      }
      final position = scrollController.position;
      final estimated = (globalIndex * avgPageHeight).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      ReaderDebugLog.log('jump_estimated', {
        'source': source ?? 'unknown',
        'global_idx': globalIndex,
        'chapter_id': loc.chapterId,
        'page_idx': loc.pageIdx,
        'avg_page_h': avgPageHeight.toStringAsFixed(1),
        'estimated_offset': estimated.round(),
        'max_extent': position.maxScrollExtent.round(),
      });
      scrollController.jumpTo(estimated);

      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        final ctx2 = pageKeys.value[keyId]?.currentContext;
        if (ctx2 == null) return;
        Scrollable.ensureVisible(
          ctx2,
          alignment: 0.0,
          duration: Duration.zero,
        );
        ReaderDebugLog.log('jump_estimated_refined', {
          'source': source ?? 'unknown',
          'global_idx': globalIndex,
        });
      });
    }

    void jumpToChapterRelative(int chapterIdx) {
      final globalIndex =
          InfinityContinuousUtils.convertChapterIndexToGlobalIndex(
        chapterIdx,
        loadedChapters.value,
        currentVisibleChapter.value.id,
      );
      if (globalIndex < 0) return;

      // Immediate state update so the slider's page-number text
      // follows the user's drag.
      if (currentChapterPageIndex.value != chapterIdx) {
        currentChapterPageIndex.value = chapterIdx;
      }
      currentIndex.value = globalIndex;

      pendingSliderTimer.value?.cancel();
      pendingSliderTimer.value =
          Timer(const Duration(milliseconds: 80), () {
        scrollToGlobalIndex(globalIndex,
            animate: isAnimationEnabled, source: 'slider');
      });
    }

    void handlePageNavigation({required bool isNext}) {
      final target = currentIndex.value + (isNext ? 1 : -1);
      scrollToGlobalIndex(target,
          animate: isAnimationEnabled, source: isNext ? 'next' : 'prev');
    }

    bool onScrollNotification(ScrollNotification notification) {
      if (notification is! ScrollUpdateNotification) return false;
      if (loadingNext.value || loadingPrevious.value) return false;

      final metrics = notification.metrics;
      final delta = notification.scrollDelta ?? 0;

      // Smoking-gun event for a backward bump: any single scroll
      // notification with a large absolute delta. Real user scrolling
      // produces small deltas (a finger drag is tens of px/frame).
      // 200+ px in one notification implies a programmatic jump or a
      // layout snap. We log immediately rather than waiting for the
      // 200ms-sampled viewport entry.
      if (delta.abs() > 200) {
        // Identify which page is currently at viewport-top so the log
        // entry tells us "the user was looking at page X, then the
        // scroll jumped to Y".
        int? topIdx;
        double? topPos;
        for (final e in pageRects.value.entries) {
          if (topIdx == null ||
              (e.value.top.abs() < (topPos ?? double.infinity))) {
            topIdx = e.key;
            topPos = e.value.top;
          }
        }
        ReaderDebugLog.log('large_scroll_jump', {
          'delta': delta.round(),
          'pixels_before': (metrics.pixels - delta).round(),
          'pixels_after': metrics.pixels.round(),
          'viewport_top_idx': topIdx ?? -1,
          'viewport_top_y': (topPos ?? 0).toStringAsFixed(1),
          'loaded_chs': loadedChapters.value.length,
        });
      }

      if (delta.abs() < 2.0) return false;

      final now = DateTime.now();
      const cooldown = Duration(milliseconds: 600);

      final atEnd = metrics.pixels >=
          metrics.maxScrollExtent -
              InfinityContinuousConfig.scrollExtentTolerance;
      final atStart = metrics.pixels <=
          metrics.minScrollExtent +
              InfinityContinuousConfig.scrollExtentTolerance;

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

      if (atStart && delta < 0 && !hasReachedStart.value) {
        final prev = nextPrevChapterPair.value?.second;
        if (prev != null &&
            (lastStartScrollTime.value == null ||
                now.difference(lastStartScrollTime.value!) > cooldown)) {
          lastStartScrollTime.value = now;
          _loadPreviousChapter(
            ref,
            prev,
            loadedChapters,
            loadingPrevious,
            hasReachedStart,
            scrollController,
            pageKeys.value,
            pageRects.value,
            context,
          );
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
      child: !kIsWeb &&
              (Platform.isAndroid || Platform.isIOS) &&
              isPinchToZoomEnabled
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
      Positioned(
        right: 12,
        bottom: 96,
        child: SafeArea(
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () async {
                // Capture the exact reader state at press time. The
                // 200ms-sampled viewport entry can lag by up to 200ms,
                // which means the BUMP user is reporting may have
                // already settled by the time it logs. Snapshot the
                // raw pageRects + scroll offset right now so the log
                // contains the state-as-felt.
                final viewportHeight = MediaQuery.of(context).size.height;
                final visibleRects = pageRects.value.entries
                    .where((e) =>
                        e.value.bottom > 0 && e.value.top < viewportHeight)
                    .toList()
                  ..sort((a, b) => a.key.compareTo(b.key));
                ReaderDebugLog.log('BUMP_SNAPSHOT', {
                  'offset': scrollController.hasClients
                      ? scrollController.offset.round()
                      : -1,
                  'max_extent': scrollController.hasClients
                      ? scrollController.position.maxScrollExtent.round()
                      : -1,
                  'visible_count': visibleRects.length,
                  'visible_idxs': visibleRects
                      .map((e) =>
                          '${e.key}@${e.value.top.toStringAsFixed(0)}..${e.value.bottom.toStringAsFixed(0)}')
                      .join('|'),
                  'loaded_chs': loadedChapters.value.map((c) => c.chapterId).join(','),
                  'cur_idx': currentIndex.value,
                  'cur_visible_ch': currentVisibleChapter.value.id,
                });
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

String _pageKeyId(int chapterId, int pageIdx) => '$chapterId:$pageIdx';

class _PageLoc {
  const _PageLoc(this.chapterId, this.pageIdx, this.imageUrl);
  final int chapterId;
  final int pageIdx;
  final String imageUrl;
}

_PageLoc? _locateGlobalIndex(
  int globalIndex,
  List<({ChapterPagesDto pages, ChapterDto chapter, int chapterId})> loaded,
) {
  int cumulative = 0;
  for (final entry in loaded) {
    final n = entry.pages.pages.length;
    if (globalIndex < cumulative + n) {
      final pageIdx = globalIndex - cumulative;
      return _PageLoc(
        entry.chapterId,
        pageIdx,
        entry.pages.pages[pageIdx],
      );
    }
    cumulative += n;
  }
  return null;
}

class _FakeItemPosition {
  const _FakeItemPosition(
      this.index, this.itemLeadingEdge, this.itemTrailingEdge);
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
      final topLeft = renderObject.localToGlobal(Offset.zero);
      widget.onReport(_PageRect(
        topLeft.dy,
        topLeft.dy + renderObject.size.height,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
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
    return ZoomView(
      controller: scrollController,
      scrollAxis: scrollDirection,
      maxScale: InfinityContinuousConfig.maxZoomScale,
      doubleTapDrag: true,
      forceHoldOnPointerDown: true,
      child: child,
    );
  }
}

Future<void> _loadNextChapter(
  WidgetRef ref,
  ChapterDto nextChapter,
  ValueNotifier<
          List<({ChapterPagesDto pages, ChapterDto chapter, int chapterId})>>
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
    if (pages == null) {
      hasReachedEnd.value = true;
      return;
    }
    final exists =
        loadedChapters.value.any((e) => e.chapterId == nextChapter.id);
    if (exists) return;
    loadedChapters.value = [
      ...loadedChapters.value,
      (pages: pages, chapter: nextChapter, chapterId: nextChapter.id),
    ];
    if (context.mounted) {
      InfinityContinuousFeedback.showNextChapterLoadedFeedback(
          context, nextChapter.name);
    }
  } catch (_) {
    hasReachedEnd.value = true;
  } finally {
    loadingNext.value = false;
  }
}

/// Back-load the previous chapter without the user seeing a jump.
///
/// Picks the page closest to the viewport top as the "anchor",
/// records its screen-space top in pixels, then prepends the chapter.
/// After the rebuild has laid out, looks up the anchor widget by its
/// stable ``(chapterId, pageIdx)`` GlobalKey, measures where it landed
/// via ``localToGlobal``, and adjusts ``scrollController.offset`` so
/// the anchor sits at the same screen position it did before.
///
/// The anchor approach handles arbitrary prepended heights and page
/// heights — including pages taller than the viewport — without
/// needing to estimate the prepended chapter's pixel height. The only
/// failure mode is image-loading-after-restore changing the prepended
/// chapter's height; in practice the placeholders are close enough to
/// the rendered height that any residual drift is sub-page.
Future<void> _loadPreviousChapter(
  WidgetRef ref,
  ChapterDto previousChapter,
  ValueNotifier<
          List<({ChapterPagesDto pages, ChapterDto chapter, int chapterId})>>
      loadedChapters,
  ValueNotifier<bool> loadingPrevious,
  ValueNotifier<bool> hasReachedStart,
  ScrollController scrollController,
  Map<String, GlobalKey> pageKeys,
  Map<int, _PageRect> pageRects,
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
    final exists =
        loadedChapters.value.any((e) => e.chapterId == previousChapter.id);
    if (exists) return;

    GlobalKey? anchorKey;
    double anchorTopBefore = 0;
    {
      int? anchorGlobalIdx;
      double bestDist = double.infinity;
      for (final e in pageRects.entries) {
        final dist = e.value.top.abs();
        if (dist < bestDist) {
          bestDist = dist;
          anchorGlobalIdx = e.key;
          anchorTopBefore = e.value.top;
        }
      }
      if (anchorGlobalIdx != null) {
        final loc =
            _locateGlobalIndex(anchorGlobalIdx, loadedChapters.value);
        if (loc != null) {
          anchorKey = pageKeys[_pageKeyId(loc.chapterId, loc.pageIdx)];
        }
      }
    }

    loadedChapters.value = [
      (
        pages: pages,
        chapter: previousChapter,
        chapterId: previousChapter.id
      ),
      ...loadedChapters.value,
    ];
    // Indices shifted; drop stale rects so we don't trip visibility
    // math before the new reports arrive.
    pageRects.clear();

    if (anchorKey != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        final ctx = anchorKey!.currentContext;
        if (ctx == null) return;
        final renderObject = ctx.findRenderObject();
        if (renderObject is! RenderBox || !renderObject.attached) return;
        final currentTop = renderObject.localToGlobal(Offset.zero).dy;
        final currentOffset = scrollController.offset;
        final delta = currentTop - anchorTopBefore;
        final desired = currentOffset + delta;
        final clamped = desired.clamp(
          scrollController.position.minScrollExtent,
          scrollController.position.maxScrollExtent,
        );
        if ((clamped - currentOffset).abs() > 0.5) {
          scrollController.jumpTo(clamped);
        }
        ReaderDebugLog.log('prev_chapter_anchor_restore', {
          'top_before': anchorTopBefore.toStringAsFixed(1),
          'top_after': currentTop.toStringAsFixed(1),
          'delta': delta.toStringAsFixed(1),
          'old_offset': currentOffset.round(),
          'new_offset': clamped.round(),
        });
      });
    }

    if (context.mounted) {
      InfinityContinuousFeedback.showPreviousChapterLoadedFeedback(
          context, previousChapter.name);
    }
  } catch (_) {
    hasReachedStart.value = true;
  } finally {
    loadingPrevious.value = false;
  }
}
