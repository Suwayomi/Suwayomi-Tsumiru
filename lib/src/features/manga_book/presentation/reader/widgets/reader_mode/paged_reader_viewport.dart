// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../../../constants/enum.dart';
import '../../../../../../widgets/custom_circular_progress_indicator.dart';
import '../reader_wrapper.dart';
import 'double_page_view.dart';
import 'paged_display_window.dart';
import 'paged_spread_mapping.dart';

enum _DragOwner { page, pager }

enum _PanDirection { left, right, up, down }

enum _TapAction { previous, next, menu }

class PagedReaderController {
  _PagedReaderViewportState? _state;

  void _attach(_PagedReaderViewportState state) => _state = state;

  void _detach(_PagedReaderViewportState state) {
    if (_state == state) _state = null;
  }

  void jumpToRaw(int rawIndex) => _state?.jumpToRaw(rawIndex);

  void next() => _state?.moveByCommand(1);

  void previous() => _state?.moveByCommand(-1);

  bool get isAtFirst => _state?.isAtFirstDisplay ?? false;

  bool get isAtLast => _state?.isAtLastDisplay ?? false;
}

/// Continuous multi-chapter paged viewport.
///
/// Renders a [PagedDisplayWindow] — the prev/current/next chapters composed
/// into ONE display list with virtual transition cards between them — so paging
/// across a chapter boundary is just a page turn inside the same pager (no route
/// rebuild). The host swaps in a fresh window (append/prepend a chapter) and
/// this widget re-anchors to the same content on [didUpdateWidget]. Progress is
/// reported as `(chapterId, raw)` so the host can address the VISIBLE chapter.
class PagedReaderViewport extends StatefulWidget {
  const PagedReaderViewport({
    super.key,
    required this.controller,
    required this.window,
    required this.initialDisplayIndex,
    required this.axis,
    required this.reverse,
    required this.animateTransitions,
    required this.pageFit,
    required this.pageSize,
    required this.centerMargin,
    required this.rotateWide,
    required this.rotateWideInvert,
    required this.reversePair,
    required this.cropBorders,
    required this.onPageWide,
    required this.onChapterPageChanged,
    required this.transitionBuilder,
    required this.pinchEnabled,
    required this.doubleTapToZoom,
    required this.disableZoomIn,
    required this.disableZoomOut,
    required this.navigateToPan,
    this.onIdle,
    this.onReachedStartEdge,
    this.onReachedEndEdge,
  });

  final PagedReaderController controller;
  final PagedDisplayWindow window;
  final int initialDisplayIndex;
  final Axis axis;
  final bool reverse;
  final bool animateTransitions;
  final BoxFit pageFit;
  final Size? pageSize;
  final CenterMarginType centerMargin;
  final bool rotateWide;
  final bool rotateWideInvert;
  final bool reversePair;
  final bool cropBorders;

  /// Reports a wide (landscape) page for the given chapter so the host can
  /// re-chunk that chapter's mapping. Chapter-scoped: two chapters can each
  /// have a wide page 0.
  final void Function(int chapterId, int raw, bool isWide) onPageWide;

  /// Reports the current reading position as `(chapterId, furthest raw page)`
  /// — the read-progress contract, addressed to the visible chapter.
  final void Function(int chapterId, int raw) onChapterPageChanged;

  /// Builds the card shown for a virtual chapter-boundary transition slot.
  final Widget Function(TransitionDisplay) transitionBuilder;

  /// Fired whenever the viewport settles onto a page (mount, page turn, jump,
  /// re-anchor, or a bounce). The host uses this to apply an idle-gated window
  /// swap without disrupting an in-progress drag/animation.
  final VoidCallback? onIdle;

  /// The outer edges of the window just bounce; these let the host surface
  /// start/end-of-manga feedback.
  final VoidCallback? onReachedStartEdge;
  final VoidCallback? onReachedEndEdge;

  final bool pinchEnabled;
  final bool doubleTapToZoom;
  final bool disableZoomIn;
  final bool disableZoomOut;
  final bool navigateToPan;

  @override
  State<PagedReaderViewport> createState() => _PagedReaderViewportState();
}

class _PagedReaderViewportState extends State<PagedReaderViewport>
    with TickerProviderStateMixin {
  static const double _touchSlop = 12;
  static const double _tapSlop = 18;
  static const double _pageTurnThreshold = 0.18;
  static const double _pageTurnVelocity = 650;
  static const double _panFlingVelocity = 700;
  static const double _panFlingDistanceFactor = 0.2;
  static const double _neutralScale = 1;
  static const Duration _tapDelay = Duration(milliseconds: 220);
  // Must stay shorter than _tapDelay: a double-tap has to be recognised before
  // the single-tap timer fires, or a slow double-tap runs both actions.
  static const Duration _doubleTapWindow = Duration(milliseconds: 200);
  static const Duration _longPressDelay = Duration(milliseconds: 480);
  static const Duration _maxSettleDuration = Duration(milliseconds: 180);
  static const Duration _minSettleDuration = Duration(milliseconds: 70);
  static const Duration _panFlingDuration = Duration(milliseconds: 400);
  static const Duration _doubleTapZoomDuration = Duration(milliseconds: 200);
  static const Curve _settleCurve = Curves.easeOutCubic;

  late int _displayIndex;
  late final AnimationController _pageAnimation;
  late final AnimationController _panAnimation;
  Animation<double>? _pageTween;
  Animation<Offset>? _panTween;
  double _dragOffset = 0;
  Size _viewportSize = Size.zero;
  final Map<int, Offset> _pointers = {};
  // Keyed by (chapterId, page identity), not display index — a late wide page
  // re-chunks a chapter's mapping and shifts display indices, and two chapters
  // can share a raw index, so the chapter disambiguates equal raws.
  final Map<({int chapterId, PageUnit unit}), _PageZoomController>
      _zoomControllers = {};

  Offset? _lastSinglePosition;
  Offset _totalDrag = Offset.zero;
  _DragOwner? _dragOwner;
  bool _multiTouchActive = false;
  bool _gestureHadMultiplePointers = false;
  bool _interruptedByAnimation = false;
  bool _longPressActive = false;
  Timer? _longPressTimer;
  Timer? _singleTapTimer;
  DateTime? _lastTapAt;
  Offset? _lastTapPosition;
  double? _pinchStartDistance;
  double _pinchStartScale = 1;
  Offset _pinchStartOffset = Offset.zero;
  Offset? _pinchStartFocal;
  VelocityTracker? _velocityTracker;
  int? _velocityPointer;
  _PageZoomController? _panAnimationTarget;
  late final AnimationController _zoomAnimation;
  Animation<double>? _zoomScaleTween;
  Animation<Offset>? _zoomOffsetTween;
  _PageZoomController? _zoomAnimationTarget;

  @override
  void initState() {
    super.initState();
    _displayIndex = _clampDisplay(widget.initialDisplayIndex);
    _pageAnimation = AnimationController(vsync: this);
    _pageAnimation.addListener(() {
      setState(() => _dragOffset = _pageTween?.value ?? _dragOffset);
    });
    _pageAnimation.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _pageTween = null;
      }
    });
    _panAnimation = AnimationController(vsync: this);
    _panAnimation.addListener(() {
      final target = _panAnimationTarget;
      final value = _panTween?.value;
      if (target == null || value == null) return;
      target.offset = value;
    });
    _panAnimation.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _panTween = null;
        _panAnimationTarget = null;
      }
    });
    _zoomAnimation = AnimationController(vsync: this);
    _zoomAnimation.addListener(() {
      final target = _zoomAnimationTarget;
      final scale = _zoomScaleTween?.value;
      final offset = _zoomOffsetTween?.value;
      if (target == null || scale == null || offset == null) return;
      target.setScaleOffset(scale, offset);
    });
    _zoomAnimation.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _zoomScaleTween = null;
        _zoomOffsetTween = null;
        _zoomAnimationTarget = null;
      }
    });
    widget.controller._attach(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _emitRawPage();
    });
  }

  @override
  void didUpdateWidget(PagedReaderViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._detach(this);
      widget.controller._attach(this);
    }
    // The host makes a NEW window instance per swap (append/prepend). Re-anchor
    // to the same content so a prepend that shifts every index doesn't jump the
    // page the user is reading.
    if (!identical(oldWidget.window, widget.window)) {
      _reanchor(oldWidget.window);
    }
    _syncZoomBounds();
  }

  @override
  void dispose() {
    widget.controller._detach(this);
    _pageAnimation.dispose();
    _panAnimation.dispose();
    _zoomAnimation.dispose();
    _longPressTimer?.cancel();
    _singleTapTimer?.cancel();
    for (final controller in _zoomControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _reanchor(PagedDisplayWindow oldWindow) {
    final item = (_displayIndex >= 0 && _displayIndex < oldWindow.length)
        ? oldWindow.items[_displayIndex]
        : null;
    var target = -1;
    if (item is SpreadDisplay) {
      target =
          widget.window.chapterRawToDisplay(item.chapterId, item.entry.first.raw);
    } else if (item is TransitionDisplay) {
      // Anchor to the chapter being ENTERED (its first page). For an
      // end-of-window "next chapter" card that doesn't know its target yet, fall
      // back to the LAST page of the chapter just finished — never its first,
      // which would throw the reader back to that chapter's start.
      if (item.toChapterId != null) {
        target = widget.window.firstDisplayOf(item.toChapterId!);
      }
      if (target < 0 && item.fromChapterId != null) {
        target = widget.window.lastDisplayOf(item.fromChapterId!);
      }
    }
    _displayIndex =
        target >= 0 ? target : _clampDisplay(widget.initialDisplayIndex);
    _dragOffset = 0;
    _emitRawPage();
  }

  void jumpToRaw(int rawIndex) {
    _stopPanAnimation();
    final chapterId = _currentChapterId();
    final target = chapterId == null
        ? -1
        : widget.window.chapterRawToDisplay(chapterId, rawIndex);
    if (target < 0 || target == _displayIndex) {
      _emitRawPage();
      return;
    }
    setState(() {
      _displayIndex = target;
      _dragOffset = 0;
    });
    _emitRawPage();
  }

  void moveByCommand(int delta) {
    if (delta == 0 || _pageAnimation.isAnimating) return;
    _stopPanAnimation();
    if (widget.navigateToPan && _panCurrentPage(_commandPanDirection(delta))) {
      return;
    }
    _animateToDisplay(_displayIndex + delta);
  }

  bool get isAtFirstDisplay => _displayIndex <= 0;

  bool get isAtLastDisplay =>
      !widget.window.isEmpty && _displayIndex >= widget.window.length - 1;

  int _clampDisplay(int index) {
    if (widget.window.isEmpty) return 0;
    return index.clamp(0, widget.window.length - 1).toInt();
  }

  void _notifyIdle() => widget.onIdle?.call();

  void _emitRawPage() {
    if (widget.window.isEmpty) {
      _notifyIdle();
      return;
    }
    final progress = widget.window.displayToChapterProgressRaw(_displayIndex);
    if (progress != null) {
      widget.onChapterPageChanged(progress.chapterId, progress.raw);
    }
    _notifyIdle();
  }

  /// True when [index] is a transition card or out of range — no zoom / pages /
  /// long-press there.
  bool _isTransitionSlot(int index) {
    if (index < 0 || index >= widget.window.length) return true;
    return widget.window.items[index] is! SpreadDisplay;
  }

  /// The chapter shown at the current slot; scans outward when the slot is a
  /// transition card so a seek still resolves to a chapter.
  int? _currentChapterId() {
    final here = widget.window.displayToChapterRaw(_displayIndex);
    if (here != null) return here.chapterId;
    for (var d = 1; d < widget.window.length; d++) {
      final before = widget.window.displayToChapterRaw(_displayIndex - d);
      if (before != null) return before.chapterId;
      final after = widget.window.displayToChapterRaw(_displayIndex + d);
      if (after != null) return after.chapterId;
    }
    return null;
  }

  bool _hasDisplayEntry(int index) =>
      index >= 0 && index < widget.window.length;

  void _syncZoomBounds() {
    for (final controller in _zoomControllers.values) {
      controller.configure(
        minScale: _minScale,
        maxScale: _maxScale,
        viewport: _viewportSize,
      );
    }
  }

  double get _minScale => widget.disableZoomOut ? _neutralScale : 0.5;

  double get _maxScale => widget.disableZoomIn ? 1 : 5;

  int get _axisSign =>
      widget.axis == Axis.horizontal && widget.reverse ? -1 : 1;

  double get _axisExtent => widget.axis == Axis.horizontal
      ? _viewportSize.width
      : _viewportSize.height;

  _PageZoomController? get _currentZoomOrNull {
    if (_isTransitionSlot(_displayIndex)) return null;
    return _zoomControllerFor(_displayIndex)
      ..configure(
        minScale: _minScale,
        maxScale: _maxScale,
        viewport: _viewportSize,
      );
  }

  _PageZoomController _zoomControllerFor(int displayIndex) {
    final item = widget.window.items[displayIndex] as SpreadDisplay;
    return _zoomControllers.putIfAbsent(
      (chapterId: item.chapterId, unit: item.entry.first),
      () => _PageZoomController(
        minScale: _minScale,
        maxScale: _maxScale,
      ),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    // A touch that lands mid-settle is an interrupt, not a nav tap — remember
    // so the ensuing tap is swallowed (the in-flight turn still commits on
    // cancel, so we must not also fire a second tap action on top of it).
    if (_pointers.isEmpty) {
      _interruptedByAnimation =
          _pageAnimation.isAnimating || _panAnimation.isAnimating;
    }
    _pageAnimation.stop();
    _stopPanAnimation();
    _stopZoomAnimation();
    _singleTapTimer?.cancel();
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 1) {
      _gestureHadMultiplePointers = false;
      _lastSinglePosition = event.localPosition;
      _totalDrag = Offset.zero;
      _dragOwner = null;
      _velocityPointer = event.pointer;
      _velocityTracker = VelocityTracker.withKind(event.kind)
        ..addPosition(event.timeStamp, event.localPosition);
      _longPressActive = false;
      _startLongPressTimer(event.localPosition);
      return;
    }
    _gestureHadMultiplePointers = true;
    _cancelLongPress(cancelled: true);
    _multiTouchActive = true;
    _velocityPointer = null;
    _velocityTracker = null;
    if (_pointers.length == 2) {
      final points = _pointers.values.toList();
      final zoom = _currentZoomOrNull;
      if (zoom == null) return;
      _pinchStartDistance = (points[0] - points[1]).distance;
      _pinchStartFocal = Offset.lerp(points[0], points[1], 0.5);
      _pinchStartScale = zoom.scale;
      _pinchStartOffset = zoom.offset;
      _dragOwner = _DragOwner.page;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final previous = _pointers[event.pointer];
    if (previous == null) return;
    _pointers[event.pointer] = event.localPosition;
    if (_velocityPointer == event.pointer) {
      _velocityTracker?.addPosition(event.timeStamp, event.localPosition);
    }

    if (_pointers.length >= 2) {
      _gestureHadMultiplePointers = true;
      _cancelLongPress(cancelled: true);
      _handlePinch();
      return;
    }

    final last = _lastSinglePosition;
    if (last == null) return;
    final delta = event.localPosition - last;
    _lastSinglePosition = event.localPosition;
    _totalDrag += delta;
    final previousOwner = _dragOwner;

    if (_longPressActive) {
      ReaderInputScope.maybeOf(context)?.onLongPressMoveUpdate(
        event.localPosition,
      );
      return;
    }

    if (_totalDrag.distance > _tapSlop) {
      _longPressTimer?.cancel();
    }

    if (_dragOwner == null && _totalDrag.distance > _touchSlop) {
      if (_currentZoomOrNull?.isActive ?? false) {
        _dragOwner = _DragOwner.page;
      } else {
        if (!_isMainAxisDrag(_totalDrag)) return;
        _dragOwner = _DragOwner.pager;
      }
    }

    switch (_dragOwner) {
      case _DragOwner.page:
        final pageDelta = previousOwner == null ? _totalDrag : delta;
        final zoom = _currentZoomOrNull;
        if (zoom == null) {
          final dragDelta = previousOwner == null
              ? _mainAxisDelta(_totalDrag)
              : _mainAxisDelta(delta);
          _dragOwner = _DragOwner.pager;
          _applyPagerDragDelta(dragDelta);
        } else if (!zoom.panBy(pageDelta) && _isMainAxisDrag(_totalDrag)) {
          final dragDelta = previousOwner == null
              ? _mainAxisDelta(_totalDrag)
              : _mainAxisDelta(delta);
          _dragOwner = _DragOwner.pager;
          _applyPagerDragDelta(dragDelta);
        }
        break;
      case _DragOwner.pager:
        final dragDelta = previousOwner == null
            ? _mainAxisDelta(_totalDrag)
            : _mainAxisDelta(delta);
        _applyPagerDragDelta(dragDelta);
        break;
      case null:
        break;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final releaseVelocity = _releaseVelocity(event);
    _pointers.remove(event.pointer);
    if (_longPressActive) {
      _finishLongPress();
      return;
    }
    _longPressTimer?.cancel();

    if (_multiTouchActive) {
      if (_pointers.isEmpty) {
        _resetGesture();
      } else if (_pointers.length == 1) {
        // Dropped back to one finger — resume single-touch from it. With 2+
        // still down we stay in multi-touch (and `.single` would throw).
        _lastSinglePosition = _pointers.values.single;
      }
      return;
    }

    if (_pointers.length == 1) {
      _lastSinglePosition = _pointers.values.single;
      return;
    }

    if (_dragOwner == _DragOwner.pager) {
      _settleDrag(releaseVelocity: _mainAxisDelta(releaseVelocity));
    } else if (_dragOwner == _DragOwner.page) {
      _settlePagePan(releaseVelocity);
    } else if (_totalDrag.distance <= _tapSlop) {
      if (!_interruptedByAnimation) _handleTap(event.localPosition);
    }

    _resetGesture();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _finishLongPress(cancelled: true);
    if (!_multiTouchActive && _dragOwner == _DragOwner.pager) _settleDrag();
    _resetGesture();
  }

  void _resetGesture() {
    _pointers.clear();
    _lastSinglePosition = null;
    _totalDrag = Offset.zero;
    _dragOwner = null;
    _multiTouchActive = false;
    _gestureHadMultiplePointers = false;
    _interruptedByAnimation = false;
    _pinchStartDistance = null;
    _pinchStartFocal = null;
    _velocityPointer = null;
    _velocityTracker = null;
  }

  void _startLongPressTimer(Offset position) {
    if (_isTransitionSlot(_displayIndex)) return;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDelay, () {
      if (!mounted ||
          _gestureHadMultiplePointers ||
          _pointers.length != 1 ||
          _totalDrag.distance > _tapSlop) {
        return;
      }
      _longPressActive = true;
      ReaderInputScope.maybeOf(context)?.onLongPressStart(position);
    });
  }

  void _cancelLongPress({bool cancelled = false}) {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _finishLongPress(cancelled: cancelled);
  }

  void _finishLongPress({bool cancelled = false}) {
    if (!_longPressActive) return;
    _longPressActive = false;
    final callbacks = ReaderInputScope.maybeOf(context);
    if (cancelled) {
      callbacks?.onLongPressCancel();
    } else {
      callbacks?.onLongPressEnd();
    }
  }

  void _claimLongPressArena() {}

  void _handlePinch() {
    if (!widget.pinchEnabled || widget.disableZoomIn) return;
    final zoom = _currentZoomOrNull;
    if (zoom == null) return;
    final startDistance = _pinchStartDistance;
    final startFocal = _pinchStartFocal;
    if (startDistance == null || startDistance == 0 || startFocal == null) {
      return;
    }
    final points = _pointers.values.toList();
    final distance = (points[0] - points[1]).distance;
    final focal = Offset.lerp(points[0], points[1], 0.5)!;
    final scale = (_pinchStartScale * distance / startDistance)
        .clamp(_minScale, _maxScale)
        .toDouble();
    zoom
      ..offset = _pinchStartOffset + (focal - startFocal)
      ..setScaleAround(scale, focal);
  }

  void _handleTap(Offset position) {
    // No double-tap-to-zoom → nothing to disambiguate, so act immediately
    // instead of holding every tap for _tapDelay (a felt page-turn latency).
    if (!widget.doubleTapToZoom || widget.disableZoomIn) {
      _handleSingleTap(position);
      return;
    }

    final now = DateTime.now();
    final previousTapAt = _lastTapAt;
    final previousTapPosition = _lastTapPosition;
    _lastTapAt = now;
    _lastTapPosition = position;

    if (previousTapAt != null &&
        now.difference(previousTapAt) <= _doubleTapWindow &&
        previousTapPosition != null &&
        (previousTapPosition - position).distance <= _tapSlop * 2) {
      _singleTapTimer?.cancel();
      _lastTapAt = null;
      _lastTapPosition = null;
      _handleDoubleTap(position);
      return;
    }

    _singleTapTimer = Timer(_tapDelay, () {
      _lastTapAt = null;
      _lastTapPosition = null;
      if (!mounted) return;
      _handleSingleTap(position);
    });
  }

  void _handleDoubleTap(Offset position) {
    if (!widget.doubleTapToZoom || widget.disableZoomIn) {
      _handleSingleTap(position);
      return;
    }
    final zoom = _currentZoomOrNull;
    if (zoom == null) {
      _handleSingleTap(position);
      return;
    }
    final target = zoom.scale > _neutralScale + 0.05
        ? _neutralScale
        : math.min(2.0, _maxScale);
    _animateZoomTo(zoom, zoom.scaleAroundTarget(target, position));
  }

  /// Animate a page's zoom to a target scale/offset (double-tap), so it eases
  /// in instead of snapping — matching the webtoon reader's zoom feel.
  void _animateZoomTo(
      _PageZoomController zoom, ({double scale, Offset offset}) end) {
    // reset() drives the controller to `dismissed`, which fires the status
    // listener that clears these tweens — so it has to run BEFORE we build them.
    // A second double-tap arrives with the controller sitting at `completed`, so
    // resetting after assignment would null the tweens it just created and the
    // zoom would never animate (page stuck zoomed).
    _zoomAnimation
      ..stop()
      ..reset();
    _zoomAnimationTarget = zoom;
    _zoomScaleTween = Tween<double>(begin: zoom.scale, end: end.scale).animate(
        CurvedAnimation(parent: _zoomAnimation, curve: Curves.easeOutCubic));
    _zoomOffsetTween = Tween<Offset>(begin: zoom.offset, end: end.offset)
        .animate(
            CurvedAnimation(parent: _zoomAnimation, curve: Curves.easeOutCubic));
    _zoomAnimation
      ..duration = _doubleTapZoomDuration
      ..forward();
  }

  void _handleSingleTap(Offset position) {
    final callbacks = ReaderInputScope.maybeOf(context);
    if (callbacks == null) return;
    switch (_tapActionFor(position, _viewportSize, callbacks)) {
      case _TapAction.previous:
        callbacks.onPrevious();
        break;
      case _TapAction.next:
        callbacks.onNext();
        break;
      case _TapAction.menu:
        callbacks.onTap();
        break;
    }
  }

  _TapAction _tapActionFor(
    Offset position,
    Size size,
    ReaderInputCallbacks callbacks,
  ) {
    final layout = callbacks.navigationLayout;
    if (layout == ReaderNavigationLayout.disabled ||
        layout == ReaderNavigationLayout.defaultNavigation) {
      return _TapAction.menu;
    }

    final leftAction = callbacks.tapInvert.invertsHorizontal
        ? _TapAction.next
        : _TapAction.previous;
    final rightAction = callbacks.tapInvert.invertsHorizontal
        ? _TapAction.previous
        : _TapAction.next;
    final topAction = callbacks.tapInvert.invertsVertical
        ? _TapAction.next
        : _TapAction.previous;
    final bottomAction = callbacks.tapInvert.invertsVertical
        ? _TapAction.previous
        : _TapAction.next;
    final edgeWidth = size.width * (callbacks.smallerTapZones ? 0.25 : 1 / 3);
    final edgeHeight = size.height * (callbacks.smallerTapZones ? 0.25 : 1 / 3);

    return switch (layout) {
      ReaderNavigationLayout.rightAndLeft => position.dx < edgeWidth
          ? leftAction
          : position.dx > size.width - edgeWidth
              ? rightAction
              : _TapAction.menu,
      ReaderNavigationLayout.edge =>
        position.dx < edgeWidth || position.dx > size.width - edgeWidth
            ? rightAction
            : position.dy > size.height - edgeHeight
                ? leftAction
                : _TapAction.menu,
      ReaderNavigationLayout.kindlish => position.dy < size.height - edgeHeight
          ? _TapAction.menu
          : position.dx < edgeWidth
              ? leftAction
              : rightAction,
      ReaderNavigationLayout.lShaped => position.dy < edgeHeight
          ? topAction
          : position.dy > size.height - edgeHeight
              ? bottomAction
              : position.dx < edgeWidth
                  ? leftAction
                  : position.dx > size.width - edgeWidth
                      ? rightAction
                      : _TapAction.menu,
      ReaderNavigationLayout.defaultNavigation ||
      ReaderNavigationLayout.disabled =>
        _TapAction.menu,
    };
  }

  Offset _releaseVelocity(PointerUpEvent event) {
    if (_velocityPointer != event.pointer) return Offset.zero;
    _velocityTracker?.addPosition(event.timeStamp, event.localPosition);
    final velocity = _velocityTracker?.getVelocity().pixelsPerSecond;
    return velocity ?? Offset.zero;
  }

  void _settleDrag({double releaseVelocity = 0}) {
    if (_axisExtent <= 0) return;
    final signedDistance = -_dragOffset * _axisSign;
    final signedVelocity = -releaseVelocity * _axisSign;
    if (signedDistance.abs() > _touchSlop &&
        signedVelocity.abs() > _pageTurnVelocity) {
      _animateToDisplay(
        _displayIndex + (signedVelocity > 0 ? 1 : -1),
      );
      return;
    }

    final progress = signedDistance / _pageTurnExtent;
    if (progress > _pageTurnThreshold) {
      _animateToDisplay(_displayIndex + 1);
      return;
    }
    if (progress < -_pageTurnThreshold) {
      _animateToDisplay(_displayIndex - 1);
      return;
    }
    _animateOffsetTo(0);
  }

  // One display slot (single page, spread, or transition card) always travels a
  // full viewport, so the turn threshold is the full extent — halving it for
  // spreads made them commit a turn at half the drag distance.
  double get _pageTurnExtent => _axisExtent;

  double _mainAxisDelta(Offset offset) =>
      widget.axis == Axis.horizontal ? offset.dx : offset.dy;

  double _crossAxisDelta(Offset offset) =>
      widget.axis == Axis.horizontal ? offset.dy : offset.dx;

  bool _isMainAxisDrag(Offset offset) =>
      _mainAxisDelta(offset).abs() >= _crossAxisDelta(offset).abs();

  void _settlePagePan(Offset releaseVelocity) {
    final zoom = _currentZoomOrNull;
    if (zoom == null) return;
    final speed = releaseVelocity.distance;
    if (!zoom.isActive || speed < _panFlingVelocity) return;

    final maxDistance = _viewportSize.longestSide * 0.9;
    final distance = math.min(speed * _panFlingDistanceFactor, maxDistance);
    final factor = distance / speed;
    final target = zoom.clampOffset(
      zoom.offset + releaseVelocity.scale(factor, factor),
    );
    final travel = (target - zoom.offset).distance;
    if (travel < 1) return;

    _panAnimation
      ..stop()
      ..duration = _panFlingDuration
      ..reset();
    _panAnimationTarget = zoom;
    _panTween = Tween<Offset>(
      begin: zoom.offset,
      end: target,
    ).animate(CurvedAnimation(parent: _panAnimation, curve: Curves.decelerate));
    _panAnimation.forward();
  }

  void _stopPanAnimation() {
    if (!_panAnimation.isAnimating) return;
    _panAnimation.stop();
    _panTween = null;
    _panAnimationTarget = null;
  }

  void _stopZoomAnimation() {
    if (!_zoomAnimation.isAnimating) return;
    _zoomAnimation.stop();
    _zoomScaleTween = null;
    _zoomOffsetTween = null;
    _zoomAnimationTarget = null;
  }

  void _animateToDisplay(int targetDisplay) {
    // The window's OUTER edges just bounce (the host surfaces start/end-of-manga
    // feedback). Interior transition cards are ordinary slots and page normally.
    if (targetDisplay < 0) {
      widget.onReachedStartEdge?.call();
      _animateOffsetTo(0);
      return;
    }
    if (targetDisplay >= widget.window.length) {
      widget.onReachedEndEdge?.call();
      _animateOffsetTo(0);
      return;
    }
    final delta = targetDisplay - _displayIndex;
    if (delta == 0) {
      _animateOffsetTo(0);
      return;
    }
    final targetOffset = -delta * _axisSign * _axisExtent;
    _animateOffsetTo(targetOffset, onComplete: () {
      if (!mounted) return;
      setState(() {
        _displayIndex = targetDisplay;
        _dragOffset = 0;
      });
      _emitRawPage();
    });
  }

  void _applyPagerDragDelta(double dragDelta) {
    setState(() {
      _dragOffset += dragDelta;
    });
  }

  void _animateOffsetTo(double target, {VoidCallback? onComplete}) {
    final duration = _settleDuration(target);
    if (duration == Duration.zero || _axisExtent <= 0) {
      setState(() => _dragOffset = target == 0 ? 0 : target);
      onComplete?.call();
      // onComplete may re-anchor/tear down — don't setState afterwards if gone.
      if (target != 0 && mounted) setState(() => _dragOffset = 0);
      if (target == 0) _notifyIdle();
      return;
    }
    _pageAnimation
      ..stop()
      ..duration = duration
      ..reset();
    _pageTween = Tween<double>(
      begin: _dragOffset,
      end: target,
    ).animate(CurvedAnimation(parent: _pageAnimation, curve: _settleCurve));
    _pageAnimation.forward().whenCompleteOrCancel(() {
      if (!mounted) return;
      onComplete?.call();
      if (target == 0) {
        setState(() => _dragOffset = 0);
        _notifyIdle();
      }
    });
  }

  Duration _settleDuration(double target) {
    if (!widget.animateTransitions || _axisExtent <= 0) return Duration.zero;
    final remaining =
        ((target - _dragOffset).abs() / _axisExtent).clamp(0.0, 1.0);
    final minMs = _minSettleDuration.inMilliseconds;
    final maxMs = _maxSettleDuration.inMilliseconds;
    return Duration(
        milliseconds: minMs + ((maxMs - minMs) * remaining).round());
  }

  _PanDirection _commandPanDirection(int delta) {
    if (widget.axis == Axis.vertical) {
      return delta > 0 ? _PanDirection.down : _PanDirection.up;
    }
    if (delta > 0) {
      return widget.reverse ? _PanDirection.left : _PanDirection.right;
    }
    return widget.reverse ? _PanDirection.right : _PanDirection.left;
  }

  bool _panCurrentPage(_PanDirection direction) {
    final zoom = _currentZoomOrNull;
    if (zoom == null) return false;
    if (!zoom.canPan(direction)) return false;
    return zoom.panByDirection(direction);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.window.isEmpty) {
      return const Center(child: CenterSorayomiShimmerIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        _syncZoomBounds();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: _claimLongPressArena,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (final index in _visibleDisplayIndexes())
                    _PositionedDisplayEntry(
                      axis: widget.axis,
                      offset: _entryOffset(index),
                      child: _buildDisplayEntry(index),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Iterable<int> _visibleDisplayIndexes() sync* {
    for (var index = _displayIndex - 1; index <= _displayIndex + 1; index++) {
      if (_hasDisplayEntry(index)) yield index;
    }
  }

  double _entryOffset(int index) =>
      (index - _displayIndex) * _axisExtent * _axisSign + _dragOffset;

  Widget _buildDisplayEntry(int index) {
    final item = widget.window.items[index];
    if (item is TransitionDisplay) {
      return widget.transitionBuilder(item);
    }
    final spread = item as SpreadDisplay;
    return _ZoomedDisplayEntry(
      controller: _zoomControllerFor(index),
      child: DoublePageView(
        entry: spread.entry,
        pages: widget.window.pagesAt(index)!,
        pageFit: widget.pageFit,
        pageSize: widget.pageSize,
        centerMargin: widget.centerMargin,
        rotateWide: widget.rotateWide,
        rotateWideInvert: widget.rotateWideInvert,
        reversePair: widget.reversePair,
        onPageWide: (raw, wide) =>
            widget.onPageWide(spread.chapterId, raw, wide),
        cropBorders: widget.cropBorders,
      ),
    );
  }
}

class _PositionedDisplayEntry extends StatelessWidget {
  const _PositionedDisplayEntry({
    required this.axis,
    required this.offset,
    required this.child,
  });

  final Axis axis;
  final double offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final translation =
        axis == Axis.horizontal ? Offset(offset, 0) : Offset(0, offset);
    return Transform.translate(offset: translation, child: child);
  }
}

class _ZoomedDisplayEntry extends StatelessWidget {
  const _ZoomedDisplayEntry({
    required this.controller,
    required this.child,
  });

  final _PageZoomController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Transform.translate(
          offset: controller.offset,
          child: Transform.scale(
            scale: controller.scale,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _PageZoomController extends ChangeNotifier {
  _PageZoomController({
    required this.minScale,
    required this.maxScale,
  }) : _scale = 1.0.clamp(minScale, maxScale).toDouble();

  double minScale;
  double maxScale;
  Size _viewport = Size.zero;
  double _scale;
  Offset _offset = Offset.zero;

  double get scale => _scale;

  Offset get offset => _offset;

  bool get isActive => _scale > 1.01;

  set offset(Offset value) {
    _offset = _clampOffset(value);
    notifyListeners();
  }

  void configure({
    required double minScale,
    required double maxScale,
    required Size viewport,
  }) {
    final oldScale = _scale;
    final oldOffset = _offset;
    final oldMinScale = this.minScale;
    final oldMaxScale = this.maxScale;
    final oldViewport = _viewport;

    this.minScale = minScale;
    this.maxScale = maxScale;
    _viewport = viewport;
    _scale = _scale.clamp(minScale, maxScale).toDouble();
    _offset = _scale <= 1.001 ? Offset.zero : _clampOffset(_offset);
    if (oldScale == _scale &&
        oldOffset == _offset &&
        oldMinScale == minScale &&
        oldMaxScale == maxScale &&
        oldViewport == viewport) {
      return;
    }
    notifyListeners();
  }

  void setScaleAround(double targetScale, Offset focal) {
    final t = scaleAroundTarget(targetScale, focal);
    setScaleOffset(t.scale, t.offset);
  }

  /// The (scale, offset) that [setScaleAround] would land on — without applying
  /// it, so the viewport can animate toward it.
  ({double scale, Offset offset}) scaleAroundTarget(
      double targetScale, Offset focal) {
    final nextScale = targetScale.clamp(minScale, maxScale).toDouble();
    if (nextScale <= 1.001) return (scale: nextScale, offset: Offset.zero);
    final scaleRatio = nextScale / _scale;
    final viewportCenter = Offset(_viewport.width / 2, _viewport.height / 2);
    final focalFromCenter = focal - viewportCenter - _offset;
    return (
      scale: nextScale,
      offset: _clampOffset(_offset - focalFromCenter * (scaleRatio - 1)),
    );
  }

  void setScaleOffset(double scale, Offset offset) {
    _scale = scale.clamp(minScale, maxScale).toDouble();
    _offset = _scale <= 1.001 ? Offset.zero : _clampOffset(offset);
    notifyListeners();
  }

  bool panBy(Offset delta) {
    if (!canPanBy(delta)) return false;
    _offset = _clampOffset(_offset + delta);
    notifyListeners();
    return true;
  }

  Offset clampOffset(Offset value) => _clampOffset(value);

  bool canPanBy(Offset delta) {
    if (_scale <= 1.01) return false;
    final next = _offset + delta;
    return _clampOffset(next) != _offset;
  }

  bool canPan(_PanDirection direction) {
    if (_scale <= 1.01) return false;
    return switch (direction) {
      _PanDirection.left => _offset.dx < _maxPan.dx - 1,
      _PanDirection.right => _offset.dx > -_maxPan.dx + 1,
      _PanDirection.up => _offset.dy < _maxPan.dy - 1,
      _PanDirection.down => _offset.dy > -_maxPan.dy + 1,
    };
  }

  bool panByDirection(_PanDirection direction) {
    final amount = switch (direction) {
      _PanDirection.left => Offset(_viewport.width * 0.8, 0),
      _PanDirection.right => Offset(-_viewport.width * 0.8, 0),
      _PanDirection.up => Offset(0, _viewport.height * 0.8),
      _PanDirection.down => Offset(0, -_viewport.height * 0.8),
    };
    return panBy(amount);
  }

  Offset get _maxPan {
    if (_scale <= 1) return Offset.zero;
    return Offset(
      _viewport.width * (_scale - 1) / 2,
      _viewport.height * (_scale - 1) / 2,
    );
  }

  Offset _clampOffset(Offset value) {
    final maxPan = _maxPan;
    return Offset(
      value.dx.clamp(-maxPan.dx, maxPan.dx).toDouble(),
      value.dy.clamp(-maxPan.dy, maxPan.dy).toDouble(),
    );
  }
}
