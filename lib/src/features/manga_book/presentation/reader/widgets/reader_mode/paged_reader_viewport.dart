// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../../../constants/enum.dart';
import '../../../../../../utils/crash/diagnostics.dart';
import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../widgets/custom_circular_progress_indicator.dart';
import '../reader_wrapper.dart';
import 'double_page_view.dart';
import 'paged_display_window.dart';
import 'paged_spread_mapping.dart';

enum _DragOwner { page, pager }

/// Captured at the drop, not reconstructed later: a settle writes its
/// intermediate positions into `_dragOffset`, so the resting offset alone can't
/// tell an abandoned turn from an unsettled drag.
class _StrandRecord {
  const _StrandRecord({
    required this.target,
    required this.offset,
    required this.extent,
    required this.generation,
    required this.owner,
    required this.stop,
    required this.interrupted,
    required this.at,
  });

  final double target;
  final double offset;
  final double extent;
  final int generation;
  final String owner;
  final String stop;
  final bool interrupted;
  final DateTime at;

  String describe() {
    final fraction = extent > 0 ? (target / extent) : 0;
    return 'stop=$stop owner=$owner gen=$generation '
        'targetPages=${fraction.toStringAsFixed(2)} '
        'atProgress=${(extent > 0 ? offset / extent : 0).toStringAsFixed(3)} '
        'interrupted=$interrupted';
  }
}

enum _PanDirection { left, right, up, down }

enum TapAction { previous, next, menu }

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

  /// Test-only displacement by [progress] of one page turn.
  @visibleForTesting
  void debugStrand(double progress) => _state?._debugStrand(progress);
}

/// Re-anchors to visible content when the host replaces the chapter window; reports chapter-relative progress.
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
    required this.pagesAtNaturalSize,
    required this.mouseScrollSpeed,
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
    this.clock = DateTime.now,
  });

  /// Injectable wall clock: widget-test timers advance without changing DateTime.now.
  final DateTime Function() clock;

  final PagedReaderController controller;
  final PagedDisplayWindow window;
  final int initialDisplayIndex;
  final Axis axis;
  final bool reverse;
  final bool animateTransitions;
  final BoxFit pageFit;
  final Size? pageSize;

  final bool pagesAtNaturalSize;

  final double mouseScrollSpeed;

  final CenterMarginType centerMargin;
  final bool rotateWide;
  final bool rotateWideInvert;
  final bool reversePair;
  final bool cropBorders;

  /// Chapter-scoped: two chapters may each have a wide page at raw index zero.
  final void Function(int chapterId, int raw, bool isWide) onPageWide;

  /// Reports the current reading position as `(chapterId, furthest raw page)`
  /// — the read-progress contract, addressed to the visible chapter.
  final void Function(int chapterId, int raw) onChapterPageChanged;

  final Widget Function(TransitionDisplay) transitionBuilder;

  /// Fires after every settle, including mount/jump/bounce, so the host can apply staged window swaps.
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
  // Android double-tap timeout in milliseconds.
  static const int _doubleTapWindowMs = 300;
  // Must outlast _doubleTapWindow, or a slow double tap fires both actions.
  static const Duration _tapDelay = Duration(
    milliseconds: _doubleTapWindowMs + 20,
  );
  static const Duration _doubleTapWindow = Duration(
    milliseconds: _doubleTapWindowMs,
  );
  static const Duration _longPressDelay = Duration(milliseconds: 480);
  static const Duration _maxSettleDuration = Duration(milliseconds: 180);
  static const Duration _minSettleDuration = Duration(milliseconds: 70);
  static const Duration _panFlingDuration = Duration(milliseconds: 400);
  static const Duration _doubleTapZoomDuration = Duration(milliseconds: 200);
  static const Curve _settleCurve = Curves.easeOutCubic;

  /// A stranded turn needs a higher commit threshold than release intent to avoid skipping a page.
  static const double _restCommitThreshold = 0.9;

  static const Duration _diagnosticInterval = Duration(seconds: 5);
  static const int _maxDiagnosticsPerSession = 20;

  late int _displayIndex;
  late final AnimationController _pageAnimation;
  late final AnimationController _panAnimation;
  Animation<double>? _pageTween;
  Animation<Offset>? _panTween;
  double _dragOffset = 0;

  /// Bumped whenever a turn in flight is abandoned, so its completion can't
  /// commit a target that no longer matches where the pager ended up.
  int _motionGeneration = 0;

  /// Set while a settle owes a completion. Between an animation ending and its
  /// completion microtask the pager legitimately sits a full page from its slot,
  /// and the rest guard would pre-empt the commit.
  bool _commitPending = false;

  String _lastMotionStop = 'none';
  _StrandRecord? _strand;
  DateTime? _lastDiagnosticAt;
  int _diagnosticCount = 0;
  Size _viewportSize = Size.zero;
  final Map<int, Offset> _pointers = {};
  // Key by chapter and page identity; wide-page remapping shifts display indices.
  final Map<({int chapterId, PageUnit unit}), _PageZoomController>
  _zoomControllers = {};

  final Map<({int chapterId, PageUnit unit}), Map<int, Size>> _naturalSizes =
      {};

  Offset? _lastSinglePosition;
  Offset _totalDrag = Offset.zero;
  _DragOwner? _dragOwner;
  bool _multiTouchActive = false;
  bool _gestureHadMultiplePointers = false;
  bool _interruptedByAnimation = false;

  /// Set when a pointer is cancelled with others still down, so the rest of
  /// that gesture can't be mistaken for a tap.
  bool _suppressTap = false;
  bool _longPressActive = false;
  Timer? _longPressTimer;
  Timer? _singleTapTimer;
  DateTime? _lastTapAt;
  Offset? _lastTapPosition;
  double? _pinchStartDistance;

  /// Which two fingers the pinch baseline was measured from. Swapping a finger
  /// mid-pinch changes the pair, and the old baseline would jump the zoom.
  Set<int>? _pinchPointers;
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
    // Re-anchor on window replacement so prepending cannot move the visible content.
    if (!identical(oldWidget.window, widget.window)) {
      _reanchor(oldWidget.window);
      _clearPendingTap();
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
    _abandonMotion('reanchor');

    final item = (_displayIndex >= 0 && _displayIndex < oldWindow.length)
        ? oldWindow.items[_displayIndex]
        : null;
    var target = -1;
    if (item is SpreadDisplay) {
      target = widget.window.chapterRawToDisplay(
        item.chapterId,
        item.entry.first.raw,
      );
    } else if (item is TransitionDisplay) {
      // A transition is content too: rebuilding spread mappings (e.g. when a
      // wide page is decoded) must not turn the notice into the next page.
      target = widget.window.items.indexOf(item);
      if (target < 0 && (item.isStart || item.isEnd)) {
        // Match interior transitions by both chapters; boundary cards preserve their one known side.
        target = widget.window.items.indexWhere(
          (candidate) =>
              candidate is TransitionDisplay &&
              (item.isEnd
                  ? candidate.fromChapterId == item.fromChapterId
                  : candidate.toChapterId == item.toChapterId),
        );
      }
      if (target < 0 && item.toChapterId != null) {
        target = widget.window.firstDisplayOf(item.toChapterId!);
      }
      if (target < 0 && item.fromChapterId != null) {
        target = widget.window.lastDisplayOf(item.fromChapterId!);
      }
    }
    _displayIndex = target >= 0
        ? target
        : _clampDisplay(widget.initialDisplayIndex);
    _dragOffset = 0;
    // didUpdateWidget runs during build; defer ancestor notification.
    Future.microtask(() {
      if (mounted) _emitRawPage();
    });
  }

  /// Stop old motion before replacing its target; stale completions must not commit another page.
  void _abandonMotion(String reason) {
    _motionGeneration++;
    // Abandoned motion owes no completion; clear this so the rest guard can run.
    _commitPending = false;
    _lastMotionStop = reason;
    _pageAnimation.stop();
    _pageTween = null;
    _stopPanAnimation();
    _stopZoomAnimation();
  }

  void jumpToRaw(int rawIndex) {
    _abandonMotion('seek');
    final chapterId = _currentChapterId();
    final target = chapterId == null
        ? -1
        : widget.window.chapterRawToDisplay(chapterId, rawIndex);
    if (target < 0 || target == _displayIndex) {
      // _abandonMotion may have killed a settle whose commit never ran; a jump
      // resolving to the current page must still land the pager back on it.
      if (_dragOffset != 0) setState(() => _dragOffset = 0);
      _emitRawPage();
      return;
    }
    _clearPendingTap();
    setState(() {
      _displayIndex = target;
      _dragOffset = 0;
    });
    _emitRawPage();
  }

  void moveByCommand(int delta) {
    if (delta == 0 || _pageAnimation.isAnimating) return;
    _abandonMotion('command');
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

  bool _isTransitionSlot(int index) {
    if (index < 0 || index >= widget.window.length) return true;
    return widget.window.items[index] is! SpreadDisplay;
  }

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
        minMultiplier: _minMultiplier,
        maxMultiplier: _maxMultiplier,
        viewport: _viewportSize,
      );
    }
  }

  /// Original size pins minimum zoom at 1:1.
  double get _minMultiplier =>
      widget.disableZoomOut || widget.pagesAtNaturalSize ? 1 : 0.5;

  double get _maxMultiplier => widget.disableZoomIn ? 1 : 5;

  int get _axisSign =>
      widget.axis == Axis.horizontal && widget.reverse ? -1 : 1;

  double get _axisExtent => widget.axis == Axis.horizontal
      ? _viewportSize.width
      : _viewportSize.height;

  _PageZoomController? get _currentZoomOrNull {
    if (_isTransitionSlot(_displayIndex)) return null;
    return _zoomControllerFor(_displayIndex)..configure(
      minMultiplier: _minMultiplier,
      maxMultiplier: _maxMultiplier,
      viewport: _viewportSize,
    );
  }

  _PageZoomController _zoomControllerFor(int displayIndex) {
    final item = widget.window.items[displayIndex] as SpreadDisplay;
    return _zoomControllers.putIfAbsent(
      (chapterId: item.chapterId, unit: item.entry.first),
      () => _PageZoomController(
        minMultiplier: _minMultiplier,
        maxMultiplier: _maxMultiplier,
      ),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    // A touch interrupting a settle must not also fire navigation after the turn commits.
    if (_pointers.isEmpty) {
      _interruptedByAnimation =
          _pageAnimation.isAnimating ||
          _panAnimation.isAnimating ||
          _zoomAnimation.isAnimating;
    }
    if (_pageAnimation.isAnimating) _lastMotionStop = 'touch';
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
      // Choose turn or zoom once; a second finger must not abandon an in-progress page turn.
      if (_dragOwner == _DragOwner.pager || _dragOffset != 0) return;
      final zoom = _currentZoomOrNull;
      if (zoom == null) return;
      _capturePinchBaseline(zoom);
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
      ReaderInputScope.maybeOf(
        context,
      )?.onLongPressMoveUpdate?.call(event.localPosition);
      return;
    }

    if (_totalDrag.distance > _tapSlop) {
      _longPressTimer?.cancel();
    }

    if (_dragOwner == null && _totalDrag.distance > _touchSlop) {
      // Only claim panning on an axis with room; cross-axis drift must not swallow a page-turn swipe.
      if (_currentZoomOrNull?.canPanAlong(_totalDrag) ?? false) {
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
      _enforcePagerRest();
      return;
    }
    _longPressTimer?.cancel();

    if (_multiTouchActive) {
      if (_pointers.isEmpty) {
        _settleAfterGesture(releaseVelocity);
        _resetGesture();
      } else if (_pointers.length == 1) {
        // Resume single-touch only with one remaining pointer; .single throws with multiple fingers.
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
      if (!_interruptedByAnimation && !_suppressTap) {
        _handleTap(event.localPosition);
      }
    }
    // A page-owned gesture (or swallowed tap) can end with the pager still
    // displaced by an abandoned turn — never let it rest between slots.
    if (_dragOwner != _DragOwner.pager &&
        _dragOffset != 0 &&
        !_pageAnimation.isAnimating) {
      _settleDrag();
    }

    _resetGesture();
  }

  /// Wheel input pans while room remains, then turns pages.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (event.kind != PointerDeviceKind.mouse) return;
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    final raw = dy != 0 ? dy : dx;
    if (raw == 0) return;
    final zoom = _currentZoomOrNull;
    final pan = Offset(-dx, -dy) * widget.mouseScrollSpeed;
    if (zoom != null && pan != Offset.zero && zoom.panBy(pan)) return;
    moveByCommand(raw > 0 ? 1 : -1);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _clearPendingTap();
    _finishLongPress(cancelled: true);
    if (_dragOwner == _DragOwner.pager || _dragOffset != 0) _settleDrag();
    if (_pointers.isNotEmpty) {
      // Fingers are still down. Wiping them here would make the next release
      // look like a fresh tap and turn the page.
      _suppressTap = true;
      _dragOwner = null;
      _totalDrag = Offset.zero;
      _lastSinglePosition = _pointers.values.first;
      return;
    }
    _resetGesture();
  }

  /// Settle residual pager motion even when the gesture ends as a one-finger pan.
  void _settleAfterGesture(Offset releaseVelocity) {
    if (_dragOwner == _DragOwner.page) {
      _settlePagePan(releaseVelocity);
    } else if (_dragOwner == _DragOwner.pager || _dragOffset != 0) {
      _settleDrag(releaseVelocity: _mainAxisDelta(releaseVelocity));
    }
  }

  void _resetGesture() {
    _pointers.clear();
    _lastSinglePosition = null;
    _totalDrag = Offset.zero;
    _dragOwner = null;
    _multiTouchActive = false;
    _gestureHadMultiplePointers = false;
    _interruptedByAnimation = false;
    _suppressTap = false;
    _pinchStartDistance = null;
    _pinchPointers = null;
    _pinchStartFocal = null;
    _velocityPointer = null;
    _velocityTracker = null;
  }

  void _startLongPressTimer(Offset position) {
    if (_isTransitionSlot(_displayIndex)) return;
    // Nothing consumes a long press: don't run a timer that would swallow the
    // gesture and, with it, the tap that was meant to turn the page.
    if (ReaderInputScope.maybeOf(context)?.onLongPressStart == null) return;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDelay, () {
      if (!mounted ||
          _gestureHadMultiplePointers ||
          _pointers.length != 1 ||
          _totalDrag.distance > _tapSlop) {
        return;
      }
      _longPressActive = true;
      ReaderInputScope.maybeOf(context)?.onLongPressStart?.call(position);
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
      callbacks?.onLongPressCancel?.call();
    } else {
      callbacks?.onLongPressEnd?.call();
    }
  }

  void _claimLongPressArena() {}

  /// Rebase pinch distance and offset whenever the pointer pair changes.
  void _capturePinchBaseline(_PageZoomController zoom) {
    final points = _pointers.values.toList();
    if (points.length < 2) return;
    _pinchPointers = _pointers.keys.toSet();
    _pinchStartDistance = (points[0] - points[1]).distance;
    _pinchStartFocal = Offset.lerp(points[0], points[1], 0.5);
    _pinchStartScale = zoom.scale;
    _pinchStartOffset = zoom.offset;
  }

  void _handlePinch() {
    if (!widget.pinchEnabled || widget.disableZoomIn) return;
    if (_dragOwner == _DragOwner.pager) return;
    final zoom = _currentZoomOrNull;
    if (zoom == null) return;
    if (_pointers.length == 2 &&
        !setEquals(_pinchPointers, _pointers.keys.toSet())) {
      _capturePinchBaseline(zoom);
    }
    final startDistance = _pinchStartDistance;
    final startFocal = _pinchStartFocal;
    if (startDistance == null || startDistance == 0 || startFocal == null) {
      return;
    }
    final points = _pointers.values.toList();
    final distance = (points[0] - points[1]).distance;
    final focal = Offset.lerp(points[0], points[1], 0.5)!;
    final scale = (_pinchStartScale * distance / startDistance)
        .clamp(zoom.minScale, zoom.maxScale)
        .toDouble();
    zoom
      ..offset = _pinchStartOffset + (focal - startFocal)
      ..setScaleAround(scale, focal);
  }

  // A tap left armed across a page change can act on, or zoom, whichever
  // page replaced the one it landed on.
  void _clearPendingTap() {
    _singleTapTimer?.cancel();
    _singleTapTimer = null;
    _lastTapAt = null;
    _lastTapPosition = null;
  }

  void _handleTap(Offset position) {
    // Without double-tap zoom, act immediately rather than delaying navigation.
    if (!widget.doubleTapToZoom || widget.disableZoomIn) {
      _handleSingleTap(position);
      return;
    }

    final now = widget.clock();
    final previousTapAt = _lastTapAt;
    final previousTapPosition = _lastTapPosition;
    _clearPendingTap();

    if (previousTapAt != null &&
        now.difference(previousTapAt) <= _doubleTapWindow &&
        previousTapPosition != null &&
        (previousTapPosition - position).distance <= _tapSlop * 2) {
      _handleDoubleTap(position);
      return;
    }

    // Too far apart to pair: fire the stranded tap now. Must happen before
    // arming this one, since acting on it can change the page and clear state.
    if (previousTapAt != null && previousTapPosition != null) {
      _handleSingleTap(previousTapPosition);
    }

    _lastTapAt = now;
    _lastTapPosition = position;
    _singleTapTimer = Timer(_tapDelay, () {
      _clearPendingTap();
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
    final target = zoom.scale > zoom.baseScale + 0.05
        ? zoom.baseScale
        : math.min(zoom.baseScale * 2, zoom.maxScale);
    _animateZoomTo(zoom, zoom.scaleAroundTarget(target, position));
  }

  void _animateZoomTo(
    _PageZoomController zoom,
    ({double scale, Offset offset}) end,
  ) {
    // Reset before assigning tweens: reset fires the listener that clears them.
    _zoomAnimation
      ..stop()
      ..reset();
    if (context.reduceMotion) {
      zoom.setScaleOffset(end.scale, end.offset);
      return;
    }
    _zoomAnimationTarget = zoom;
    _zoomScaleTween = Tween<double>(begin: zoom.scale, end: end.scale).animate(
      CurvedAnimation(parent: _zoomAnimation, curve: Curves.easeOutCubic),
    );
    _zoomOffsetTween = Tween<Offset>(begin: zoom.offset, end: end.offset)
        .animate(
          CurvedAnimation(parent: _zoomAnimation, curve: Curves.easeOutCubic),
        );
    _zoomAnimation
      ..duration = _doubleTapZoomDuration
      ..forward();
  }

  void _handleSingleTap(Offset position) {
    final callbacks = ReaderInputScope.maybeOf(context);
    if (callbacks == null) return;
    switch (_tapActionFor(position, _viewportSize, callbacks)) {
      case TapAction.previous:
        callbacks.onPrevious();
        break;
      case TapAction.next:
        callbacks.onNext();
        break;
      case TapAction.menu:
        callbacks.onTap();
        break;
    }
  }

  TapAction _tapActionFor(
    Offset position,
    Size size,
    ReaderInputCallbacks callbacks,
  ) => tapActionForZone(
    position: position,
    size: size,
    layout: callbacks.navigationLayout,
    tapInvert: callbacks.tapInvert,
    smallerTapZones: callbacks.smallerTapZones,
  );

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
      _animateToDisplay(_displayIndex + (signedVelocity > 0 ? 1 : -1));
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

  // Each display slot travels one full viewport, including spreads.
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
    // Outer window edges bounce; interior transition cards page normally.
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
    _animateOffsetTo(
      targetOffset,
      onComplete: () {
        if (!mounted) return;
        setState(() {
          _displayIndex = targetDisplay;
          _dragOffset = 0;
        });
        _emitRawPage();
      },
    );
  }

  void _applyPagerDragDelta(double dragDelta) {
    setState(() {
      _dragOffset += dragDelta;
    });
  }

  void _animateOffsetTo(double target, {VoidCallback? onComplete}) {
    // Starting a turn retires the previous one: stopping it below fires its
    // completion, which would otherwise commit the page it was aiming at.
    _motionGeneration++;
    final generation = _motionGeneration;
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
    _commitPending = true;
    _pageAnimation.forward().whenCompleteOrCancel(() {
      if (generation != _motionGeneration) {
        if (!_commitPending && _dragOffset != 0) {
          _recordStrand(target: target, generation: generation);
          _scheduleRestCheck();
        }
        return;
      }
      _commitPending = false;
      if (!mounted) return;
      onComplete?.call();
      if (target == 0) {
        setState(() => _dragOffset = 0);
        _notifyIdle();
      }
    });
  }

  void _debugStrand(double progress) {
    _motionGeneration++;
    _commitPending = false;
    _lastMotionStop = 'debug';
    _pageAnimation.stop();
    _pageTween = null;
    setState(() => _dragOffset = -progress * _axisSign * _axisExtent);
  }

  void _recordStrand({required double target, required int generation}) {
    _strand = _StrandRecord(
      target: target,
      offset: _dragOffset,
      extent: _axisExtent,
      generation: generation,
      owner: _dragOwner?.name ?? 'none',
      stop: _lastMotionStop,
      interrupted: _interruptedByAnimation,
      at: DateTime.now(),
    );
  }

  void _scheduleRestCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _enforcePagerRest();
    });
  }

  /// Enforce resting on a slot regardless of which path abandoned motion.
  void _enforcePagerRest() {
    if (_dragOffset == 0) return;
    if (_pointers.isNotEmpty) return;
    if (_pageAnimation.isAnimating) return;
    if (_commitPending) return;

    if (_axisExtent <= 0) {
      // Keeping a pixel offset with no extent lets a later, narrower layout read
      // it as a much larger fraction of a page.
      _logRestRecovery(progress: 0, action: 'zero-extent');
      setState(() => _dragOffset = 0);
      return;
    }

    final progress = -_dragOffset * _axisSign / _axisExtent;
    if (progress.abs() >= _restCommitThreshold) {
      _logRestRecovery(progress: progress, action: 'commit');
      _animateToDisplay(_displayIndex + (progress > 0 ? 1 : -1));
      return;
    }
    _logRestRecovery(progress: progress, action: 'snapback');
    _animateOffsetTo(0);
  }

  void _logRestRecovery({required double progress, required String action}) {
    final now = DateTime.now();
    final last = _lastDiagnosticAt;
    if (_diagnosticCount >= _maxDiagnosticsPerSession) return;
    if (last != null && now.difference(last) < _diagnosticInterval) return;
    _lastDiagnosticAt = now;
    _diagnosticCount++;

    final strand = _strand;
    final held = strand == null ? -1 : now.difference(strand.at).inMilliseconds;
    recordDiagnostic(
      '[${now.toIso8601String()}] reader-rest: action=$action '
      'progress=${progress.toStringAsFixed(3)} '
      'index=$_displayIndex axis=${widget.axis.name} '
      'reverse=${widget.reverse} zoom=${_currentZoomOrNull?.isActive ?? false} '
      'spread=${widget.window.items[_clampDisplay(_displayIndex)] is SpreadDisplay} '
      'heldMs=$held ${strand?.describe() ?? 'strand=none'}\n',
    );
  }

  Duration _settleDuration(double target) {
    if (!widget.animateTransitions || _axisExtent <= 0) return Duration.zero;
    final remaining = ((target - _dragOffset).abs() / _axisExtent).clamp(
      0.0,
      1.0,
    );
    final minMs = _minSettleDuration.inMilliseconds;
    final maxMs = _maxSettleDuration.inMilliseconds;
    return Duration(
      milliseconds: minMs + ((maxMs - minMs) * remaining).round(),
    );
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
        final nextViewport = Size(constraints.maxWidth, constraints.maxHeight);
        final resized = nextViewport != _viewportSize;
        _viewportSize = nextViewport;
        _syncZoomBounds();
        if (resized) _republishVisibleMetrics();
        if (_dragOffset != 0) _scheduleRestCheck();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Only claim the arena when a long press has somewhere to go.
          onLongPress:
              ReaderInputScope.maybeOf(context)?.onLongPressStart == null
              ? null
              : _claimLongPressArena,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            onPointerSignal: _onPointerSignal,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (final index in _visibleDisplayIndexes())
                    _PositionedDisplayEntry(
                      axis: widget.axis,
                      offset: _entryOffset(index),
                      child: _buildDisplayEntry(
                        index,
                        active: index == _displayIndex,
                      ),
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

  Widget _buildDisplayEntry(int index, {required bool active}) {
    final item = widget.window.items[index];
    if (item is TransitionDisplay) {
      return widget.transitionBuilder(item);
    }
    final spread = item as SpreadDisplay;
    // Clipped to its own slot: a page rendered larger than the screen (Original
    // size) must not paint over the pages either side of it.
    return ClipRect(
      child: _ZoomedDisplayEntry(
        controller: _zoomControllerFor(index),
        // Only transform the focused page; retained off-screen zoom/pan would overlap it.
        active: active,
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
          onNaturalSize: (raw, natural) =>
              _recordNaturalSize(index, spread, raw, natural),
          naturalSize: widget.pagesAtNaturalSize,
          cropBorders: widget.cropBorders,
        ),
      ),
    );
  }

  void _recordNaturalSize(
    int index,
    SpreadDisplay spread,
    int raw,
    Size natural,
  ) {
    // Cache-hit image listeners can fire during build; publish zoom metrics after the frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _recordNaturalSize(index, spread, raw, natural);
      });
      return;
    }
    if (natural.isEmpty || _viewportSize.isEmpty) return;
    final key = (chapterId: spread.chapterId, unit: spread.entry.first);
    final naturals = _naturalSizes.putIfAbsent(key, () => {});
    // A re-chunk can turn a pair into a solo page under the same key; keeping
    // the dropped page's size would leave the survivor with pair-sized bounds.
    final belongs = {
      spread.entry.first.raw,
      if (spread.entry.second != null) spread.entry.second!.raw,
    };
    final stale = naturals.keys.where((r) => !belongs.contains(r)).toList();
    naturals.removeWhere((r, _) => !belongs.contains(r));
    if (naturals[raw] == natural && stale.isEmpty) return;
    naturals[raw] = natural;

    _publishPageMetrics(index, spread);
  }

  /// Recompute metrics on resize/rotation because the image may not decode again.
  void _publishPageMetrics(int index, SpreadDisplay spread) {
    final naturals =
        _naturalSizes[(chapterId: spread.chapterId, unit: spread.entry.first)];
    if (naturals == null || naturals.isEmpty || _viewportSize.isEmpty) return;

    final slot = _slotSize(spread);
    var width = 0.0;
    var height = 0.0;
    for (final size in naturals.values) {
      final laidOut = widget.pagesAtNaturalSize
          ? size
          : applyBoxFit(widget.pageFit, size, slot).destination;
      if (laidOut.isEmpty) continue;
      width += laidOut.width;
      height = math.max(height, laidOut.height);
    }
    if (width <= 0 || height <= 0) return;

    _zoomControllerFor(
      index,
    ).setPageMetrics(content: Size(width, height), baseScale: 1);
  }

  void _republishVisibleMetrics() {
    for (final index in _visibleDisplayIndexes()) {
      final item = widget.window.items[index];
      if (item is SpreadDisplay) _publishPageMetrics(index, item);
    }
  }

  Size _slotSize(SpreadDisplay spread) {
    if (!spread.entry.isPair) {
      return Size(_viewportSize.width, _viewportSize.height);
    }
    final margin =
        widget.centerMargin == CenterMarginType.doublePage ||
            widget.centerMargin == CenterMarginType.doubleAndWide
        ? kCenterMargin
        : 0.0;
    return Size(
      math.max(0, _viewportSize.width - margin) / 2,
      _viewportSize.height,
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
    final translation = axis == Axis.horizontal
        ? Offset(offset, 0)
        : Offset(0, offset);
    return Transform.translate(offset: translation, child: child);
  }
}

class _ZoomedDisplayEntry extends StatelessWidget {
  const _ZoomedDisplayEntry({
    required this.controller,
    required this.active,
    required this.child,
  });

  final _PageZoomController controller;

  /// Only the focused page applies retained zoom/pan; neighbours render at base fit.
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Transform.translate(
          offset: controller.offset,
          child: Transform.scale(scale: controller.scale, child: child),
        );
      },
      child: child,
    );
  }
}

class _PageZoomController extends ChangeNotifier {
  _PageZoomController({
    required this.minMultiplier,
    required this.maxMultiplier,
  }) : _scale = 1;

  /// Zoom bounds as multiples of [baseScale] (1 except under Original size).
  double minMultiplier;
  double maxMultiplier;

  Size _viewport = Size.zero;

  /// The page's laid-out size at rest. Null until the image decodes; until then
  /// the page is assumed to fill the viewport.
  Size? _content;

  /// Original size rests at source-pixel 1:1, so it can pan without zooming.
  double _baseScale = 1;

  double _scale;
  Offset _offset = Offset.zero;

  double get scale => _scale;

  double get baseScale => _baseScale;

  double get minScale => _baseScale * minMultiplier;

  double get maxScale => _baseScale * maxMultiplier;

  Offset get offset => _offset;

  /// Panning capacity, including Original size at rest, determines gesture ownership.
  bool get isActive => _maxPan != Offset.zero;

  set offset(Offset value) {
    _offset = _clampOffset(value);
    notifyListeners();
  }

  void configure({
    required double minMultiplier,
    required double maxMultiplier,
    required Size viewport,
  }) {
    final oldScale = _scale;
    final oldOffset = _offset;
    final oldMin = this.minMultiplier;
    final oldMax = this.maxMultiplier;
    final oldViewport = _viewport;

    this.minMultiplier = minMultiplier;
    this.maxMultiplier = maxMultiplier;
    _viewport = viewport;
    _scale = _scale.clamp(minScale, maxScale).toDouble();
    _offset = _clampOffset(_offset);
    if (oldScale == _scale &&
        oldOffset == _offset &&
        oldMin == minMultiplier &&
        oldMax == maxMultiplier &&
        oldViewport == viewport) {
      return;
    }
    notifyListeners();
  }

  /// Feeds in the page's measured layout on decode. A page still at rest
  /// follows the new resting scale; a zoomed page keeps where the reader put it.
  void setPageMetrics({required Size content, required double baseScale}) {
    if (_content == content && _baseScale == baseScale) return;
    final wasAtRest = (_scale - _baseScale).abs() < 0.001;
    _content = content;
    _baseScale = baseScale;
    if (wasAtRest) _scale = baseScale;
    _scale = _scale.clamp(minScale, maxScale).toDouble();
    _offset = _clampOffset(_offset);
    notifyListeners();
  }

  void setScaleAround(double targetScale, Offset focal) {
    final t = scaleAroundTarget(targetScale, focal);
    setScaleOffset(t.scale, t.offset);
  }

  /// Returns the target scale/offset without applying it, for animated zoom.
  ({double scale, Offset offset}) scaleAroundTarget(
    double targetScale,
    Offset focal,
  ) {
    final nextScale = targetScale.clamp(minScale, maxScale).toDouble();
    final scaleRatio = nextScale / _scale;
    final viewportCenter = Offset(_viewport.width / 2, _viewport.height / 2);
    final focalFromCenter = focal - viewportCenter - _offset;
    return (
      scale: nextScale,
      // Clamped against where we're going, not where we are — panning room
      // shrinks as you zoom out, and the old scale would allow too much.
      offset: _clampOffsetAt(
        _offset - focalFromCenter * (scaleRatio - 1),
        nextScale,
      ),
    );
  }

  void setScaleOffset(double scale, Offset offset) {
    _scale = scale.clamp(minScale, maxScale).toDouble();
    _offset = _clampOffset(offset);
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
    final next = _offset + delta;
    return _clampOffset(next) != _offset;
  }

  bool canPanAlong(Offset drag) => canPanBy(
    drag.dx.abs() >= drag.dy.abs() ? Offset(drag.dx, 0) : Offset(0, drag.dy),
  );

  bool canPan(_PanDirection direction) {
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

  Offset get _maxPan => _maxPanAt(_scale);

  /// Max pan distance, measured from the page's own box (not the viewport) so
  /// a letterboxed page can't be dragged into its own margin.
  Offset _maxPanAt(double scale) {
    final content = _content ?? _viewport;
    return Offset(
      math.max(0, (content.width * scale - _viewport.width) / 2),
      math.max(0, (content.height * scale - _viewport.height) / 2),
    );
  }

  Offset _clampOffset(Offset value) => _clampOffsetAt(value, _scale);

  Offset _clampOffsetAt(Offset value, double scale) {
    final maxPan = _maxPanAt(scale);
    return Offset(
      value.dx.clamp(-maxPan.dx, maxPan.dx).toDouble(),
      value.dy.clamp(-maxPan.dy, maxPan.dy).toDouble(),
    );
  }
}

@visibleForTesting
TapAction tapActionForZone({
  required Offset position,
  required Size size,
  required ReaderNavigationLayout layout,
  required TapInvert tapInvert,
  required bool smallerTapZones,
}) {
  final leftAction = tapInvert.invertsHorizontal
      ? TapAction.next
      : TapAction.previous;
  final rightAction = tapInvert.invertsHorizontal
      ? TapAction.previous
      : TapAction.next;
  final topAction = tapInvert.invertsVertical
      ? TapAction.next
      : TapAction.previous;
  final bottomAction = tapInvert.invertsVertical
      ? TapAction.previous
      : TapAction.next;
  final edgeWidth = size.width * (smallerTapZones ? 0.25 : 1 / 3);
  final edgeHeight = size.height * (smallerTapZones ? 0.25 : 1 / 3);

  return switch (layout) {
    ReaderNavigationLayout.rightAndLeft =>
      position.dx < edgeWidth
          ? leftAction
          : position.dx >= size.width - edgeWidth
          ? rightAction
          : TapAction.menu,
    ReaderNavigationLayout.edge =>
      position.dx < edgeWidth || position.dx >= size.width - edgeWidth
          ? rightAction
          : position.dy >= size.height - edgeHeight
          ? leftAction
          : TapAction.menu,
    ReaderNavigationLayout.kindlish =>
      position.dy < edgeHeight
          ? TapAction.menu
          : position.dx < edgeWidth
          ? leftAction
          : rightAction,
    ReaderNavigationLayout.lShaped =>
      position.dy < edgeHeight
          ? topAction
          : position.dy >= size.height - edgeHeight
          ? bottomAction
          : position.dx < edgeWidth
          ? leftAction
          : position.dx >= size.width - edgeWidth
          ? rightAction
          : TapAction.menu,
    ReaderNavigationLayout.defaultNavigation ||
    ReaderNavigationLayout.disabled => TapAction.menu,
  };
}
