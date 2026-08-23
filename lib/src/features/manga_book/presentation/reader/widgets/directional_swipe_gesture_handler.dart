// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/enum.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../widgets/zoom/single_touch_drag_recognizers.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/chapter_page/chapter_page_model.dart';
import '../utils/last_page_swipe_utils.dart';
import 'reader_gesture_state.dart';

/// Handles chapter-boundary swipes for reader modes that do not own gestures.
class DirectionalSwipeGestureHandler extends HookConsumerWidget {
  const DirectionalSwipeGestureHandler({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPressStart,
    required this.scrollDirection,
    required this.readerSwipeChapterToggle,
    required this.lastPageSwipeEnabled,
    required this.resolvedReaderMode,
    required this.currentIndex,
    required this.chapterPages,
    required this.mangaId,
    required this.prevNextChapterPair,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.pageController,
  });

  final Widget child;
  final VoidCallback onTap;
  /// Null when nothing consumes a long press — [GestureDetector] then skips
  /// the recognizer entirely rather than claiming the gesture for a no-op.
  final void Function(LongPressStartDetails)? onLongPressStart;
  final Axis scrollDirection;
  final bool readerSwipeChapterToggle;
  final bool lastPageSwipeEnabled;
  final ReaderMode resolvedReaderMode;
  final int currentIndex;
  final ChapterPagesDto chapterPages;
  final int mangaId;
  final ({ChapterDto? first, ChapterDto? second})? prevNextChapterPair;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;
  final PageController? pageController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // In vertical (webtoon / continuous / vertical-paged) modes the SingleTouch*
    // swipe recognizers are dead no-ops — their handlers early-return for
    // Axis.vertical (see :158 and :328), because chapter changes there are
    // driven by scroll / infinite-scroll, not a horizontal swipe. But they still
    // ENTER the gesture arena, and on a single-finger vertical drag they can win
    // it away from the reader's ZoomView scale recognizer. On iOS the platform
    // supplies no touch slop (DeviceGestureSettings.touchSlop is null), so the
    // drag recognizer's 18px slop is crossed before ZoomView's 36px pan slop —
    // the drag recognizer wins, ZoomView never starts its synthetic scroll, and
    // forceHoldOnPointerDown leaves the list frozen. That is the confirmed
    // iOS-only "webtoon won't scroll" bug. Since these recognizers do nothing in
    // vertical mode, don't register them at all here, leaving ZoomView's scale
    // recognizer the sole single-finger owner. Horizontal/paged modes keep them.
    if (scrollDirection == Axis.vertical) {
      return _wrapWithTapAndLongPress(child);
    }
    // Horizontal continuous mode has the same conflict while the reader is
    // zoomed in: a single-finger drag then means "pan around the zoomed
    // page", not "swipe to change page/chapter", but these recognizers would
    // still enter the arena for it and can win it away from ZoomView exactly
    // like the vertical case above. Unlike vertical, horizontal genuinely
    // needs them at 1x, so they can't be dropped outright — each recognizer
    // instead self-rejects new pointers while isZoomedIn() is true (mirrors
    // the multi-touch self-rejection they already do), which changes their
    // runtime behaviour without ever changing the widget tree shape — doing
    // that structurally (e.g. conditionally omitting the RawGestureDetector)
    // would tear down and remount the whole page list every time the zoom
    // level crosses 1x, visibly jolting the reading position.
    bool isZoomedIn() => ref.read(readerIsZoomedInProvider);
    final bool useAdvancedGestures =
        lastPageSwipeEnabled && !readerSwipeChapterToggle;
    return useAdvancedGestures
        ? _buildBoundarySwipeHandler(context, isZoomedIn)
        : _buildChapterSwipeHandler(context, isZoomedIn);
  }

  /// Tap + long-press wrapper shared by every mode. These don't fight
  /// multi-touch, so they're always safe to layer over the reader content.
  Widget _wrapWithTapAndLongPress(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: onLongPressStart,
      onTap: onTap,
      child: child,
    );
  }

  Widget _buildBoundarySwipeHandler(
    BuildContext context,
    bool Function() isZoomedIn,
  ) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        SingleTouchPanGestureRecognizer: GestureRecognizerFactoryWithHandlers<
            SingleTouchPanGestureRecognizer>(
          () => SingleTouchPanGestureRecognizer(
            debugOwner: this,
            isZoomedIn: isZoomedIn,
          ),
          (recognizer) {
            recognizer.isZoomedIn = isZoomedIn;
            recognizer.onEnd = (details) {
              final swipeDirection =
                  LastPageSwipeUtils.detectSwipeDirection(details);
              if (swipeDirection != null) {
                _handleBoundarySwipe(
                  context: context,
                  direction: swipeDirection,
                );
              }
            };
          },
        ),
      },
      child: _wrapWithTapAndLongPress(child),
    );
  }

  Widget _buildChapterSwipeHandler(
    BuildContext context,
    bool Function() isZoomedIn,
  ) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        SingleTouchHorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
                SingleTouchHorizontalDragGestureRecognizer>(
          () => SingleTouchHorizontalDragGestureRecognizer(
            debugOwner: this,
            isZoomedIn: isZoomedIn,
          ),
          (recognizer) {
            recognizer.isZoomedIn = isZoomedIn;
            recognizer.onEnd = (details) {
              _handleSwipeGesture(
                context: context,
                details: details,
                allowedAxis: Axis.vertical,
              );
            };
          },
        ),
        SingleTouchVerticalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
                SingleTouchVerticalDragGestureRecognizer>(
          () => SingleTouchVerticalDragGestureRecognizer(
            debugOwner: this,
            isZoomedIn: isZoomedIn,
          ),
          (recognizer) {
            recognizer.isZoomedIn = isZoomedIn;
            recognizer.onEnd = (details) {
              _handleSwipeGesture(
                context: context,
                details: details,
                allowedAxis: Axis.horizontal,
              );
            };
          },
        ),
      },
      child: _wrapWithTapAndLongPress(child),
    );
  }

  void _handleBoundarySwipe({
    required BuildContext context,
    required SwipeDirection direction,
  }) {
    // In webtoon / vertical-scroll modes a horizontal swipe changing chapter
    // is a terrible experience, so ignore it — the vertical scroll (and
    // infinite scroll) handle moving between chapters there.
    if (scrollDirection == Axis.vertical) return;

    if (!lastPageSwipeEnabled) return;
    final realTimePageIndex = pageController?.page?.round() ?? currentIndex;

    final pagePosition = LastPageSwipeUtils.detectPagePosition(
      currentIndex: realTimePageIndex,
      chapterPages: chapterPages,
    );

    final isAtLastPage = pagePosition == PagePosition.lastPage ||
        pagePosition == PagePosition.singlePage;
    final isAtFirstPage = pagePosition == PagePosition.firstPage ||
        pagePosition == PagePosition.singlePage;

    final navigationAction = _determineNavigationAction(
      direction: direction,
      isAtLastPage: isAtLastPage,
      isAtFirstPage: isAtFirstPage,
    );

    _executeNavigationAction(
      context: context,
      action: navigationAction,
      direction: direction,
    );
  }

  NavigationAction _determineNavigationAction({
    required SwipeDirection direction,
    required bool isAtLastPage,
    required bool isAtFirstPage,
  }) {
    if (!lastPageSwipeEnabled) return NavigationAction.pageNavigation;

    final expectedDirection =
        LastPageSwipeUtils.getExpectedSwipeDirection(resolvedReaderMode);

    if (direction == expectedDirection) {
      if (isAtLastPage) {
        return NavigationAction.nextChapter;
      } else {
        return NavigationAction.pageNavigation;
      }
    } else if (_isOppositeDirection(direction, expectedDirection)) {
      if (isAtFirstPage) {
        return NavigationAction.previousChapter;
      } else {
        return NavigationAction.pageNavigation;
      }
    }

    return NavigationAction.pageNavigation;
  }

  bool _isOppositeDirection(SwipeDirection actual, SwipeDirection expected) {
    switch (expected) {
      case SwipeDirection.left:
        return actual == SwipeDirection.right;
      case SwipeDirection.right:
        return actual == SwipeDirection.left;
      case SwipeDirection.up:
        return actual == SwipeDirection.down;
      case SwipeDirection.down:
        return actual == SwipeDirection.up;
    }
  }

  void _executeNavigationAction({
    required BuildContext context,
    required NavigationAction action,
    required SwipeDirection direction,
  }) {
    try {
      switch (action) {
        case NavigationAction.nextChapter:
          _navigateToNextChapterWithFallback(context);
          break;
        case NavigationAction.previousChapter:
          _navigateToPreviousChapterWithFallback(context);
          break;
        case NavigationAction.pageNavigation:
          _performPageNavigation(direction);
          break;
      }
    } catch (e) {
      _performPageNavigation(direction);
    }
  }

  void _navigateToNextChapterWithFallback(BuildContext context) {
    if (prevNextChapterPair?.first != null) {
      try {
        ReaderRoute(
          mangaId: mangaId,
          chapterId: prevNextChapterPair!.first!.id,
          transVertical: scrollDirection == Axis.vertical,
        ).pushReplacement(context);
      } catch (e) {
        onNextPage();
      }
    } else {
      onNextPage();
    }
  }

  void _navigateToPreviousChapterWithFallback(BuildContext context) {
    if (prevNextChapterPair?.second != null) {
      try {
        ReaderRoute(
          mangaId: mangaId,
          chapterId: prevNextChapterPair!.second!.id,
          toPrev: true,
          transVertical: scrollDirection == Axis.vertical,
          openAtEnd: true,
        ).pushReplacement(context);
      } catch (e) {
        onPreviousPage();
      }
    } else {
      onPreviousPage();
    }
  }

  void _performPageNavigation(SwipeDirection direction) {
    switch (direction) {
      case SwipeDirection.left:
      case SwipeDirection.up:
        onNextPage();
        break;
      case SwipeDirection.right:
      case SwipeDirection.down:
        onPreviousPage();
        break;
    }
  }

  void _handleSwipeGesture({
    required BuildContext context,
    required DragEndDetails details,
    required Axis allowedAxis,
  }) {
    // Manga-only gesture: in vertical/webtoon modes a horizontal swipe must
    // not change chapter (vertical scroll + infinite scroll handle that).
    if (scrollDirection == Axis.vertical) return;

    if (readerSwipeChapterToggle) {
      _handleChapterSwipe(context, details, allowedAxis);
      return;
    }

    if (!lastPageSwipeEnabled) {
      return;
    }

    if (scrollDirection != allowedAxis) {
      return;
    }

    final swipeDirection = LastPageSwipeUtils.detectSwipeDirection(details);
    if (swipeDirection == null) {
      return;
    }

    final pagePosition = LastPageSwipeUtils.detectPagePosition(
      currentIndex: currentIndex,
      chapterPages: chapterPages,
    );

    final isAtLastPage = pagePosition == PagePosition.lastPage ||
        pagePosition == PagePosition.singlePage;
    final isAtFirstPage = pagePosition == PagePosition.firstPage ||
        pagePosition == PagePosition.singlePage;

    final navigationAction = _determineNavigationAction(
      direction: swipeDirection,
      isAtLastPage: isAtLastPage,
      isAtFirstPage: isAtFirstPage,
    );

    _executeNavigationAction(
      context: context,
      action: navigationAction,
      direction: swipeDirection,
    );
  }

  void _handleChapterSwipe(
    BuildContext context,
    DragEndDetails details,
    Axis allowedAxis,
  ) {
    if (scrollDirection != allowedAxis) return;

    if (details.primaryVelocity == null) return;

    if (details.primaryVelocity! > 8) {
      _navigateToPreviousChapterWithFallback(context);
    } else {
      _navigateToNextChapterWithFallback(context);
    }
  }
}
