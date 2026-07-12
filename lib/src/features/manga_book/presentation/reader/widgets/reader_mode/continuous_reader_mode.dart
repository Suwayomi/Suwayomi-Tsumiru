// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../../../constants/enum.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/misc/app_utils.dart';
import '../../../../../../widgets/server_image.dart';
import '../../../../../../widgets/zoom/scroll_offset_to_scroll_controller.dart';
import '../../../../../settings/presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';
import '../../../../../settings/presentation/reader/widgets/reader_infinity_scrolling_mode_tile/reader_infinity_scrolling_mode_tile.dart';
import '../../../../../settings/presentation/reader/widgets/reader_paged_prefs/reader_paged_prefs.dart';
import '../../../../../settings/presentation/reader/widgets/reader_pinch_to_zoom/reader_pinch_to_zoom.dart';
import '../../../../../settings/presentation/reader/widgets/reader_webtoon_prefs/reader_webtoon_prefs.dart';
import '../../../../../settings/presentation/reader/widgets/reader_zoom_toggles/reader_zoom_toggles.dart';
import '../../../../domain/chapter/chapter_model.dart';
import '../../../../domain/chapter_page/chapter_page_model.dart';
import '../../../../domain/manga/manga_model.dart';
import '../../utils/reader_initial_page.dart';
import '../chapter_separator.dart';
import '../reader_wrapper.dart';
import 'infinity_continuous_reader_mode.dart';
import 'reader_zoom_view.dart';

const double _kViewportScrollFraction = 0.9; // ~one screen, small overlap

class _ScrollConfig {
  const _ScrollConfig._();

  static const double minVisibleAreaThreshold = 0.4;

  static const Duration programmaticNavigationDelay =
      Duration(milliseconds: 800);
}

class ContinuousReaderMode extends HookConsumerWidget {
  const ContinuousReaderMode({
    super.key,
    required this.manga,
    required this.chapter,
    required this.chapterPages,
    this.showSeparator = false,
    this.onPageChanged,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.showReaderLayoutAnimation = false,
    this.effectiveReaderMode,
    this.openAtEnd = false,
  });

  final MangaDto manga;
  final ChapterDto chapter;
  final bool showSeparator;
  final ValueSetter<int>? onPageChanged;
  final Axis scrollDirection;
  final bool reverse;
  final bool showReaderLayoutAnimation;
  final ReaderMode? effectiveReaderMode;
  final bool openAtEnd;
  final ChapterPagesDto chapterPages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infinityScrollingEnabled =
        ref.watch(infinityScrollingModeEnabledProvider).ifNull(true);

    if (infinityScrollingEnabled &&
        scrollDirection == Axis.vertical &&
        !showSeparator) {
      return InfinityContinuousReaderMode(
        manga: manga,
        chapter: chapter,
        chapterPages: chapterPages,
        onPageChanged: onPageChanged,
        scrollDirection: scrollDirection,
        reverse: reverse,
        showReaderLayoutAnimation: showReaderLayoutAnimation,
        effectiveReaderMode: effectiveReaderMode ?? ReaderMode.webtoon,
        openAtEnd: openAtEnd,
      );
    }

    final ItemScrollController scrollController =
        useMemoized(() => ItemScrollController());
    final ItemPositionsListener positionsListener =
        useMemoized(() => ItemPositionsListener.create());
    final ScrollOffsetController scrollOffsetController =
        useMemoized(() => ScrollOffsetController());
    final ScrollController zoomScrollController = useMemoized(
      () => ScrollOffsetToScrollController(
        scrollOffsetController: scrollOffsetController,
      ),
      [scrollOffsetController],
    );

    final initialIndex = readerInitialPageIndex(
      chapter: chapter,
      chapterPages: chapterPages,
      openAtEnd: openAtEnd,
    );
    final ValueNotifier<int> currentIndex = useState(initialIndex);

    final ObjectRef<Timer?> positionUpdateTimer = useRef<Timer?>(null);
    final ValueNotifier<bool> isUserScrolling = useState(false);
    final ValueNotifier<bool> isNavigatingFromSlider = useState(false);
    final ValueNotifier<int> lastReportedIndex = useState(currentIndex.value);

    useEffect(() {
      return () {
        positionUpdateTimer.value?.cancel();
        positionUpdateTimer.value = null;
      };
    }, []);

    useEffect(() {
      void listener() {
        final List<ItemPosition> positions =
            positionsListener.itemPositions.value.toList();

        if (positions.isEmpty) return;

        if (!isNavigatingFromSlider.value) {
          _updatePositionForDisplay(
            positions,
            currentIndex,
            lastReportedIndex,
            chapterPages.chapter.pageCount,
          );
        }

        isUserScrolling.value = true;
        positionUpdateTimer.value?.cancel();
        positionUpdateTimer.value =
            Timer(_ScrollConfig.programmaticNavigationDelay, () {
          isUserScrolling.value = false;
          isNavigatingFromSlider.value = false;
        });
      }

      positionsListener.itemPositions.addListener(listener);
      return () {
        positionsListener.itemPositions.removeListener(listener);
        positionUpdateTimer.value?.cancel();
      };
    }, []);

    useEffect(() {
      final ValueSetter<int>? pageChanged = onPageChanged;
      if (pageChanged != null &&
          lastReportedIndex.value != currentIndex.value) {
        pageChanged(currentIndex.value);
        lastReportedIndex.value = currentIndex.value;
      }
      return null;
    }, [currentIndex.value]);

    // "Animate page transitions": animate next/prev when ON, else jump.
    final bool isAnimationEnabled =
        ref.watch(animatePageTransitionsProvider).ifNull(true);
    final bool isPinchToZoomEnabled =
        ref.watch(pinchToZoomProvider).ifNull(true);
    final bool isDoubleTapZoomEnabled =
        ref.watch(doubleTapToZoomProvider).ifNull(true);
    final bool isZoomOutDisabled = ref.watch(disableZoomOutProvider).ifNull();

    // "Always show chapter transition": ON keeps the full prev/next
    // transition separator; OFF minimizes it.
    final bool alwaysShowTransition =
        ref.watch(alwaysShowChapterTransitionProvider).ifNull(true);

    // Long-strip smart scale: cap the strip width on wide/landscape screens
    // (vertical only). Render-only.
    final WebtoonScaleType scaleType =
        ref.watch(webtoonScaleTypeKeyProvider) ?? WebtoonScaleType.fitScreen;
    final double maxContentWidth = scrollDirection == Axis.vertical
        ? scaleType.maxContentWidth(context.width, context.height)
        : context.width;
    // Auto-crop solid borders in the long-strip.
    final bool cropBorders = ref.watch(cropBordersWebtoonProvider).ifNull();
    final wrapperReaderMode = effectiveReaderMode ??
        _continuousReaderMode(
          scrollDirection: scrollDirection,
          reverse: reverse,
          showSeparator: showSeparator,
        );

    void handleViewportScroll({required bool forward}) {
      if (!scrollController.isAttached) return;
      try {
        final ScrollPosition pos = scrollOffsetController.position;
        final double viewport = pos.viewportDimension;
        final double sign = (forward ? 1.0 : -1.0) * (reverse ? -1.0 : 1.0);
        scrollOffsetController.animateScroll(
          offset: viewport * _kViewportScrollFraction * sign,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } catch (_) {
        // Attached but not laid out yet (no ScrollPosition) — skip this press.
      }
    }

    return ReaderWrapper(
      scrollDirection: scrollDirection,
      chapterPages: chapterPages,
      chapter: chapter,
      manga: manga,
      showReaderLayoutAnimation: showReaderLayoutAnimation,
      currentIndex: currentIndex.value,
      effectiveReaderMode: wrapperReaderMode,
      onChanged: (index) {
        isNavigatingFromSlider.value = true;
        currentIndex.value = index;
        scrollController.jumpTo(index: index);
        Timer(const Duration(milliseconds: 300), () {
          isNavigatingFromSlider.value = false;
        });
      },
      onPrevious: () => _handleNavigationSafely(
        scrollController,
        positionsListener,
        isUserScrolling,
        isAnimationEnabled,
        isNext: false,
      ),
      onNext: () => _handleNavigationSafely(
        scrollController,
        positionsListener,
        isUserScrolling,
        isAnimationEnabled,
        isNext: true,
      ),
      onViewportScrollForward: () => handleViewportScroll(forward: true),
      onViewportScrollBackward: () => handleViewportScroll(forward: false),
      child: AppUtils.wrapOn(
        !kIsWeb &&
                (Platform.isAndroid || Platform.isIOS) &&
                (isPinchToZoomEnabled || isDoubleTapZoomEnabled)
            ? (Widget child) => ReaderZoomView(
                  controller: zoomScrollController,
                  scrollAxis: scrollDirection,
                  maxScale: 5,
                  // Webtoon min zoom-out rate is 0.5 unless disabled.
                  minScale: isZoomOutDisabled ? 1 : 0.5,
                  pinchEnabled: isPinchToZoomEnabled,
                  doubleTapToZoom: isDoubleTapZoomEnabled,
                  child: child,
                )
            : null,
        ScrollablePositionedList.separated(
          itemScrollController: scrollController,
          itemPositionsListener: positionsListener,
          scrollOffsetController: scrollOffsetController,
          initialScrollIndex: initialIndex,
          scrollDirection: scrollDirection,
          reverse: reverse,
          itemCount: chapterPages.chapter.pageCount,
          minCacheExtent: scrollDirection == Axis.vertical
              ? context.height * 2
              : context.width * 2,
          separatorBuilder: (BuildContext context, int index) =>
              showSeparator ? const Gap(16) : const SizedBox.shrink(),
          itemBuilder: (BuildContext context, int index) {
            Widget image = ServerImage(
              showReloadButton: true,
              fit: scrollDirection == Axis.vertical
                  ? BoxFit.fitWidth
                  : BoxFit.fitHeight,
              appendApiToUrl: false,
              cropBorders: cropBorders,
              imageUrl: chapterPages.pages[index],
              progressIndicatorBuilder: (_, __, downloadProgress) => Center(
                child: CircularProgressIndicator(
                  value: downloadProgress.progress,
                ),
              ),
              wrapper: (Widget child) => SizedBox(
                height: scrollDirection == Axis.vertical
                    ? context.height * .7
                    : null,
                width: scrollDirection != Axis.vertical
                    ? context.width * .7
                    : null,
                child: child,
              ),
            );

            // Smart-scale: centre the narrower strip on wide screens.
            if (scrollDirection == Axis.vertical &&
                maxContentWidth < context.width) {
              image = Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: image,
                ),
              );
            }

            if (index == 0 || index == chapterPages.chapter.pageCount - 1) {
              final bool reverseDirection =
                  scrollDirection == Axis.horizontal && reverse;
              final Widget separator = SizedBox(
                width: scrollDirection != Axis.vertical
                    ? context.width * .5
                    : null,
                child: ChapterSeparator(
                  manga: manga,
                  chapter: chapter,
                  isPreviousChapterSeparator: (index == 0),
                  alwaysShow: alwaysShowTransition,
                ),
              );
              return Flex(
                direction: scrollDirection,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: ((index == 0) != reverseDirection)
                    ? [separator, image]
                    : [image, separator],
              );
            } else {
              return image;
            }
          },
        ),
      ),
    );
  }

  static void _updatePositionForDisplay(
    List<ItemPosition> positions,
    ValueNotifier<int> currentIndex,
    ValueNotifier<int> lastReportedIndex,
    int itemCount,
  ) {
    if (positions.isEmpty) return;

    // When the last image is shorter than the viewport, the "most visible
    // area" heuristic below can pick a larger image above instead of the
    // last image, so currentIndex never reaches the end of the chapter and
    // mark-as-read never fires. If the last item is in view and the scroll
    // has reached its end (the last item's trailing edge is at or above
    // the viewport bottom), force currentIndex to the last page so the
    // read-marking pipeline downstream behaves correctly.
    if (itemCount > 0) {
      final int lastIndex = itemCount - 1;
      for (final ItemPosition position in positions) {
        if (position.index == lastIndex && position.itemTrailingEdge <= 1.0) {
          currentIndex.value = lastIndex;
          return;
        }
      }
    }

    ItemPosition? mostVisible;
    double bestVisibleArea = 0.0;

    for (final ItemPosition position in positions) {
      final double visibleArea = _calculateVisibleArea(position);

      if (visibleArea > bestVisibleArea &&
          visibleArea > _ScrollConfig.minVisibleAreaThreshold) {
        bestVisibleArea = visibleArea;
        mostVisible = position;
      }
    }

    if (mostVisible != null) {
      currentIndex.value = mostVisible.index;
    }
  }

  static double _calculateVisibleArea(ItemPosition position) {
    final double leadingEdge = position.itemLeadingEdge.clamp(0.0, 1.0);
    final double trailingEdge = position.itemTrailingEdge.clamp(0.0, 1.0);

    final double visibleStart = leadingEdge < 0 ? 0.0 : leadingEdge;
    final double visibleEnd = trailingEdge > 1 ? 1.0 : trailingEdge;

    return (visibleEnd - visibleStart).clamp(0.0, 1.0);
  }

  static void _handleNavigationSafely(
      ItemScrollController scrollController,
      ItemPositionsListener positionsListener,
      ValueNotifier<bool> isUserScrolling,
      bool isAnimationEnabled,
      {required bool isNext}) {
    if (isUserScrolling.value) return;

    final List<ItemPosition> positions =
        positionsListener.itemPositions.value.toList();
    if (positions.isEmpty) return;

    ItemPosition? currentPosition;
    for (final ItemPosition position in positions) {
      final double visibleArea = _calculateVisibleArea(position);
      if (visibleArea > _ScrollConfig.minVisibleAreaThreshold) {
        currentPosition = position;
        break;
      }
    }

    if (currentPosition == null) return;

    final int targetIndex;
    final double alignment;

    if (isNext) {
      if (currentPosition.itemTrailingEdge > 0.8) {
        targetIndex = currentPosition.index + 1;
        alignment = 0.0;
      } else {
        targetIndex = currentPosition.index;
        alignment = 0.0;
      }
    } else {
      if (currentPosition.itemLeadingEdge < 0.2) {
        targetIndex =
            (currentPosition.index - 1).clamp(0, double.infinity).toInt();
        alignment = 0.0;
      } else {
        targetIndex = currentPosition.index;
        alignment = 0.0;
      }
    }

    if (isAnimationEnabled) {
      scrollController.scrollTo(
        index: targetIndex,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: alignment,
      );
    } else {
      scrollController.jumpTo(
        index: targetIndex,
        alignment: alignment,
      );
    }
  }
}

ReaderMode _continuousReaderMode({
  required Axis scrollDirection,
  required bool reverse,
  required bool showSeparator,
}) {
  if (scrollDirection == Axis.horizontal) {
    return reverse
        ? ReaderMode.continuousHorizontalRTL
        : ReaderMode.continuousHorizontalLTR;
  }
  return showSeparator ? ReaderMode.continuousVertical : ReaderMode.webtoon;
}
