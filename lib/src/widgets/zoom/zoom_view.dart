// Vendored from the `zoom_view` package (v1.0.2, https://github.com/yakagami/zoom_view)
// so the reader can control pinch and scale limits independently and live.
//
// Local changes vs upstream:
//   * `minScale` / `maxScale` are read live from the widget in the scale gesture
//     (upstream froze them into `late final` fields at initState, so changing
//     "disable zoom out" needed a reader restart).
//   * Added `pinchEnabled`: when false the pinch/scale gesture is ignored (so
//     double-tap-to-zoom still works with pinch turned off), and the zoom level
//     resets to 1x when it flips off.
//   * Pinch-scale now re-centers on the live `details.localFocalPoint` on every
//     update instead of the point frozen at `onScaleStart` (upstream bug: that
//     point is whichever finger touches down FIRST, since Flutter doesn't
//     restart the gesture when the second one joins, so the zoom drifted away
//     from the actual pinch center — #372).
//   * Every computed scroll target is clamped to `[minScrollExtent,
//     maxScrollExtent]` before `jumpTo` (upstream bug: near a content edge,
//     the target could exceed the scrollable range; `jumpTo` doesn't clamp,
//     so Flutter's own out-of-range correction only kicked in on a later
//     frame and snapped straight to the boundary with no regard for the
//     tapped/pinched focal point — #372).
//
// Upstream license (MIT):
//   Copyright 2024
//   Permission is hereby granted, free of charge, to any person obtaining a copy
//   of this software and associated documentation files (the "Software"), to deal
//   in the Software without restriction... The above copyright notice and this
//   permission notice shall be included in all copies or substantial portions of
//   the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A controller for a [ZoomView] that allows programmatic control over the zoom level.
class ZoomViewController {
  _ZoomViewState? _state;

  void _attach(_ZoomViewState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  /// Whether the controller is currently attached to a [ZoomView].
  bool get isAttached => _state != null;

  /// The current scale of the attached [ZoomView].
  double get scale {
    if (!isAttached) return 1.0;
    return 1 / _state!._scale;
  }

  /// Returns the current [DragMode] of the [ZoomView]. When [ZoomView.onScaleEnd]
  /// is called, this will be the DragMode of the last gesture.
  DragMode get dragMode {
    if (!isAttached) {
      throw ("Controler is not attached to a ZoomView");
    }
    return _state!._dragMode;
  }

  /// Sets the scale of the attached [ZoomView].
  void setScale(double newScale, {Offset? focalPoint}) {
    if (!isAttached) return;
    final state = _state!;
    if (!state.mounted) return;
    final widget = state.widget;

    final size = state.context.size;
    if (size == null) return;
    final double height = size.height;
    final double width = size.width;

    final focus = focalPoint ?? Offset(width / 2, height / 2);

    final clampedUserScale = _clampDouble(newScale, widget.minScale, widget.maxScale);
    final internalNewScale = 1 / clampedUserScale;
    final double currentInternalScale = state._scale;

    final effectivePixels = _effectivePixels(
      scrollAxis: widget.scrollAxis,
      currentInternalScale: currentInternalScale,
      width: width,
      height: height,
      horizontalController: state._horizontalController,
      verticalController: state._verticalController,
    );

    final focusDx = _mainAxisFocalCoord(
      raw: focus.dx,
      dimension: width,
      axis: Axis.horizontal,
      scrollAxis: widget.scrollAxis,
      reverse: widget.reverse,
    );
    final focusDy = _mainAxisFocalCoord(
      raw: focus.dy,
      dimension: height,
      axis: Axis.vertical,
      scrollAxis: widget.scrollAxis,
      reverse: widget.reverse,
    );
    final newHorizontalPixels = _clampScrollTarget(
      axis: Axis.horizontal,
      scrollAxis: widget.scrollAxis,
      controller: state._horizontalController,
      rawCrossDimension: width,
      newInternalScale: internalNewScale,
      value: effectivePixels.horizontal +
          (currentInternalScale - internalNewScale) * focusDx,
    );
    final newVerticalPixels = _clampScrollTarget(
      axis: Axis.vertical,
      scrollAxis: widget.scrollAxis,
      controller: state._verticalController,
      rawCrossDimension: height,
      newInternalScale: internalNewScale,
      value: effectivePixels.vertical +
          (currentInternalScale - internalNewScale) * focusDy,
    );

    state._updateScale(internalNewScale);
    state._verticalController.jumpTo(newVerticalPixels);
    state._horizontalController.jumpTo(newHorizontalPixels);
    state._updateLastScale(internalNewScale);
  }

  /// Sets the scale of the attached [ZoomView] to a new value with an animation.
  void setScaleWithAnimation(
    double newScale, {
    Duration duration = const Duration(milliseconds: 150),
    Offset? focalPoint,
  }) {
    if (!isAttached) return;
    final state = _state!;
    if (!state.mounted) return;
    final widget = state.widget;

    final size = state.context.size;
    if (size == null) return;
    final double height = size.height;
    final double width = size.width;

    final focus = focalPoint ?? Offset(width / 2, height / 2);

    final clampedUserScale = _clampDouble(newScale, widget.minScale, widget.maxScale);
    final internalNewScale = 1 / clampedUserScale;
    final double initialInternalScale = state._scale;

    if (duration <= Duration.zero) {
      setScale(newScale, focalPoint: focalPoint);
      return;
    }

    // Detach any listeners from a still-running animation before starting a new
    // one, so a rapid second double-tap (or a pan mid-zoom) doesn't stack them.
    state._clearScaleAnimationListeners();
    state._masterAnimationController.stop();
    state._masterAnimationController.duration = duration;

    final scaleAnimation = Tween<double>(begin: initialInternalScale, end: internalNewScale)
        .animate(
            CurvedAnimation(parent: state._masterAnimationController, curve: Curves.easeInOut));

    final initialEffectivePixels = _effectivePixels(
      scrollAxis: widget.scrollAxis,
      currentInternalScale: initialInternalScale,
      width: width,
      height: height,
      horizontalController: state._horizontalController,
      verticalController: state._verticalController,
    );
    double currentEffectiveHorizontalPixels = initialEffectivePixels.horizontal;
    double currentEffectiveVerticalPixels = initialEffectivePixels.vertical;
    final focusDx = _mainAxisFocalCoord(
      raw: focus.dx,
      dimension: width,
      axis: Axis.horizontal,
      scrollAxis: widget.scrollAxis,
      reverse: widget.reverse,
    );
    final focusDy = _mainAxisFocalCoord(
      raw: focus.dy,
      dimension: height,
      axis: Axis.vertical,
      scrollAxis: widget.scrollAxis,
      reverse: widget.reverse,
    );
    bool firstFrame = true;
    bool secondFrame = false;
    void listener() {
      final double newAnimatedInternalScale = scaleAnimation.value;
      final double previousAnimatedInternalScale = state._scale;

      currentEffectiveHorizontalPixels = _clampScrollTarget(
        axis: Axis.horizontal,
        scrollAxis: widget.scrollAxis,
        controller: state._horizontalController,
        rawCrossDimension: width,
        newInternalScale: newAnimatedInternalScale,
        value: currentEffectiveHorizontalPixels +
            (previousAnimatedInternalScale - newAnimatedInternalScale) *
                focusDx,
      );
      currentEffectiveVerticalPixels = _clampScrollTarget(
        axis: Axis.vertical,
        scrollAxis: widget.scrollAxis,
        controller: state._verticalController,
        rawCrossDimension: height,
        newInternalScale: newAnimatedInternalScale,
        value: currentEffectiveVerticalPixels +
            (previousAnimatedInternalScale - newAnimatedInternalScale) *
                focusDy,
      );
      state._updateScale(newAnimatedInternalScale);

      if (!firstFrame && !secondFrame) {
        state._verticalController.jumpTo(currentEffectiveVerticalPixels);
        state._horizontalController.jumpTo(currentEffectiveHorizontalPixels);
      }
      if (secondFrame) {
        secondFrame = false;
      }
      if (firstFrame) {
        //the first and second frame jumps have the same value,
        // so we only play the first frame but on the second tick,
        // otherwise the view crashes into the viewport and flickers
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (state.mounted) {
            state._verticalController.jumpTo(currentEffectiveVerticalPixels);
            state._horizontalController.jumpTo(currentEffectiveHorizontalPixels);
          }
        });
        secondFrame = true;
      }
      firstFrame = false;
    }

    state._activeScaleListener = listener;
    state._masterAnimationController.addListener(listener);

    void statusListener(status) {
      if (status == AnimationStatus.completed) {
        //ensure final value is correct
        setScale(1 / internalNewScale, focalPoint: focus);
        state._updateLastScale(internalNewScale);
        state._clearScaleAnimationListeners();
      }
    }

    state._activeScaleStatusListener = statusListener;
    state._masterAnimationController.addStatusListener(statusListener);
    state._masterAnimationController.forward(from: 0.0);
  }
}

///Wrapper for [ZoomView] that handles the controller automatically
class ZoomListView extends StatefulWidget {
  final ListView child;
  final double minScale;
  final double maxScale;

  /// If true, enables double tap dragging to zoom.
  final bool doubleTapDrag;

  /// If true, enables double tap to zoom using the [gestureHandler] or a default one.
  final bool doubleTapZoom;

  /// Callback invoked any time the scale of the [ZoomView] changes.
  final ValueChanged<double>? onScaleChanged;

  /// Optional controller. If not provided, one is created internally.
  final ZoomViewController? zoomViewController;

  /// Optional gesture handler. If [doubleTapZoom] is true and this is null,
  /// a default handler is created zooming to min(maxScale, 3.0).
  final ZoomViewGestureHandler? gestureHandler;

  const ZoomListView({
    super.key,
    required this.child,
    this.minScale = 1.0,
    this.maxScale = 4.0,
    this.doubleTapDrag = false,
    this.doubleTapZoom = true,
    this.onScaleChanged,
    this.zoomViewController,
    this.gestureHandler,
  });

  @override
  State<ZoomListView> createState() => _ZoomListViewState();
}

class _ZoomListViewState extends State<ZoomListView> {
  late ZoomViewController _controller;
  ZoomViewGestureHandler? _handler;

  @override
  void initState() {
    if (widget.child.controller == null) {
      throw Exception(
        "List does not have a controller. Add a controller to your list",
      );
    }
    super.initState();
    _controller = widget.zoomViewController ?? ZoomViewController();
    _updateHandler();
  }

  @override
  void didUpdateWidget(ZoomListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.zoomViewController != oldWidget.zoomViewController) {
      _controller = widget.zoomViewController ?? ZoomViewController();
    }
    if (widget.doubleTapZoom != oldWidget.doubleTapZoom ||
        widget.maxScale != oldWidget.maxScale ||
        widget.gestureHandler != oldWidget.gestureHandler) {
      _updateHandler();
    }
  }

  void _updateHandler() {
    if (widget.gestureHandler != null) {
      _handler = widget.gestureHandler;
    } else if (widget.doubleTapZoom) {
      _handler = ZoomViewGestureHandler(
        controller: _controller,
        zoomLevels: [min(widget.maxScale, 3.0), 1.0],
      );
    } else {
      _handler = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ZoomView(
      controller: widget.child.controller!,
      scrollAxis: widget.child.scrollDirection,
      maxScale: widget.maxScale,
      minScale: widget.minScale,
      doubleTapDrag: widget.doubleTapDrag,
      zoomViewController: _controller,
      onDoubleTap: _handler?.onDoubleTap,
      onScaleChanged: widget.onScaleChanged,
      child: widget.child,
    );
  }
}

enum DragMode { pan, doubleTapDrag, pinchScale, none }

///Details for the [ZoomView.onScaleEnd] callback.
final class ZoomViewScaleEndDetails {
  ///The number of pointers that were on the screen when the scale gesture ended.
  final int pointerCount;

  ///The final scale of the [ZoomView] when the gesture ended.
  final double scale;

  ZoomViewScaleEndDetails({
    required this.pointerCount,
    required this.scale,
  });
}

///Allows a ListView or other Scrollables that implement ScrollPosition and
///jumpTo(offset) in their controller to be zoomed and scrolled.
class ZoomView extends StatefulWidget {
  const ZoomView({
    super.key,
    required this.child,
    required this.controller,
    this.zoomViewController,
    this.maxScale = 4.0,
    this.minScale = 1.0,
    this.onDoubleTap,
    this.scrollAxis = Axis.vertical,
    this.reverse = false,
    this.doubleTapDrag = false,
    this.forceHoldOnPointerDown = false,
    this.pinchEnabled = true,
    this.onScaleChanged,
    this.onScaleEnd,
  });

  /// Callback invoked after a double tap.
  /// The [TapDownDetails] from the gesture are provided.
  /// This is commonly used with [ZoomViewGestureHandler.onDoubleTap].
  final void Function(TapDownDetails details)? onDoubleTap;
  final Widget child;
  final ScrollController controller;

  /// A controller to programmatically control the zoom level.
  final ZoomViewController? zoomViewController;

  ///scrollAxis must be set to Axis.horizontal if the Scrollable is horizontal
  final Axis scrollAxis;

  ///Must be set to true if the wrapped Scrollable itself is built with
  ///`reverse: true` (e.g. an RTL manga's page list). The scrollable's own
  ///`pixels` still increase in the same logical direction either way, but
  ///which SCREEN direction that corresponds to flips — so every focal-point
  ///recentering formula below, which maps a screen-space drag/pinch delta on
  ///[scrollAxis] onto a `pixels` delta, needs its sign flipped to match.
  ///Only [scrollAxis] itself is affected: the cross axis is ZoomView's own
  ///synthetic pan controller, never the wrapped (possibly reversed) list.
  final bool reverse;

  ///The maximum scale that the ZoomView can be zoomed to. Set to double.infinity to allow infinite zoom in
  final double maxScale;

  ///The minimum scale that the ZoomView can be zoomed to. Set to 0 to allow infinite zoom out
  final double minScale;

  ///If true, enables double tap dragging to zoom.
  final bool doubleTapDrag;

  ///Forces the vertical and horizontal scrollables to stop panning any time
  ///a pointer touches the screen. This is needed when the Scale gesture does
  ///not automatically win the arena and the scrollables are still scrolling
  ///from a previous fling gesture.
  final bool forceHoldOnPointerDown;

  ///If false, the pinch/scale gesture is ignored so two fingers never zoom.
  ///Double-tap-to-zoom (via [onDoubleTap]) still works. The zoom level resets
  ///to 1x when this flips from true to false.
  final bool pinchEnabled;

  ///Callback invoked any time the scale of the [ZoomView] changes.
  final void Function(double scale)? onScaleChanged;

  ///Callback invoked when a scale gesture ends.
  final void Function(ZoomViewScaleEndDetails details)? onScaleEnd;

  @override
  State<ZoomView> createState() => _ZoomViewState();
}

class _ZoomViewState extends State<ZoomView> with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    if (widget.scrollAxis == Axis.vertical) {
      _verticalController = widget.controller;
      _horizontalController = ScrollController();
    } else {
      _verticalController = ScrollController();
      _horizontalController = widget.controller;
    }
    _verticalTouchHandler = _TouchHandler(controller: _verticalController);
    _horizontalTouchHandler = _TouchHandler(controller: _horizontalController);

    _masterAnimationController = AnimationController(vsync: this);

    widget.zoomViewController?._attach(this);
  }

  @override
  void didUpdateWidget(ZoomView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.zoomViewController != oldWidget.zoomViewController) {
      oldWidget.zoomViewController?._detach();
      widget.zoomViewController?._attach(this);
    }
    // Turning pinch off resets any current zoom back to 1x. Deferred a frame so
    // the layout (context.size) is available.
    if (oldWidget.pinchEnabled && !widget.pinchEnabled && _scale != 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resetScaleToOne();
      });
    }
  }

  /// Snaps the zoom back to 1x, correcting the scroll offsets the same way
  /// [ZoomViewController.setScale] does.
  void _resetScaleToOne() {
    final size = context.size;
    if (size == null) return;
    // Both scroll positions must be attached before we read pixels / jumpTo —
    // during a mode transition a child scrollable can be momentarily detached.
    if (!_verticalController.hasClients || !_horizontalController.hasClients) {
      return;
    }
    final focus = Offset(size.width / 2, size.height / 2);
    final currentInternalScale = _scale;
    const internalNewScale = 1.0;
    final effectivePixels = _effectivePixels(
      scrollAxis: widget.scrollAxis,
      currentInternalScale: currentInternalScale,
      width: size.width,
      height: size.height,
      horizontalController: _horizontalController,
      verticalController: _verticalController,
    );
    final focusDx = _mainAxisFocalCoord(
      raw: focus.dx,
      dimension: size.width,
      axis: Axis.horizontal,
      scrollAxis: widget.scrollAxis,
      reverse: widget.reverse,
    );
    final focusDy = _mainAxisFocalCoord(
      raw: focus.dy,
      dimension: size.height,
      axis: Axis.vertical,
      scrollAxis: widget.scrollAxis,
      reverse: widget.reverse,
    );
    final newHorizontalPixels = _clampScrollTarget(
      axis: Axis.horizontal,
      scrollAxis: widget.scrollAxis,
      controller: _horizontalController,
      rawCrossDimension: size.width,
      newInternalScale: internalNewScale,
      value: effectivePixels.horizontal +
          (currentInternalScale - internalNewScale) * focusDx,
    );
    final newVerticalPixels = _clampScrollTarget(
      axis: Axis.vertical,
      scrollAxis: widget.scrollAxis,
      controller: _verticalController,
      rawCrossDimension: size.height,
      newInternalScale: internalNewScale,
      value: effectivePixels.vertical +
          (currentInternalScale - internalNewScale) * focusDy,
    );
    _updateScale(internalNewScale);
    _verticalController.jumpTo(newVerticalPixels);
    _horizontalController.jumpTo(newHorizontalPixels);
    _updateLastScale(internalNewScale);
  }

  @override
  void dispose() {
    _clearScaleAnimationListeners();
    _masterAnimationController.dispose();
    if (widget.scrollAxis == Axis.vertical) {
      _horizontalController.dispose();
    } else {
      _verticalController.dispose();
    }
    widget.zoomViewController?._detach();
    super.dispose();
  }

  ///The current scale of the ZoomView
  double _scale = 1;

  ///The scale of the ZoomView before the last scale update event
  double _lastScale = 1;

  ///Used for trackpad pointerEvents to determine if the user is panning or scaling
  late TrackPadState _trackPadState;

  ///Total distance the trackpad has moved vertically since the last scale start event
  Size _globalTrackpadDistance = Size.zero;

  late final AnimationController _masterAnimationController;

  // The listener + status listener registered by the currently-running
  // setScaleWithAnimation. Tracked so a new zoom (or an interrupting pan) can
  // detach the previous ones first — a stopped (never "completed") animation
  // otherwise leaves them attached and the next run drives several accumulated
  // listeners that fight over _scale.
  VoidCallback? _activeScaleListener;
  void Function(AnimationStatus)? _activeScaleStatusListener;

  void _clearScaleAnimationListeners() {
    final listener = _activeScaleListener;
    if (listener != null) {
      _masterAnimationController.removeListener(listener);
      _activeScaleListener = null;
    }
    final statusListener = _activeScaleStatusListener;
    if (statusListener != null) {
      _masterAnimationController.removeStatusListener(statusListener);
      _activeScaleStatusListener = null;
    }
  }

  late final ScrollController _verticalController;
  late final ScrollController _horizontalController;

  late final _TouchHandler _verticalTouchHandler;
  late final _TouchHandler _horizontalTouchHandler;

  // Internal scale bounds are inverted (internal = 1 / userScale), so the
  // MAX user scale maps to the MIN internal value and vice-versa. Read live
  // from the widget so "disable zoom out" applies without a reader restart.
  double get _minInternalScale => 1 / widget.maxScale;
  double get _maxInternalScale => 1 / widget.minScale;

  Offset? _previousDragPosition;

  DragMode _dragMode = DragMode.none;

  late TapDownDetails _tapDownDetails;

  final VelocityTracker _tracker = VelocityTracker.withKind(
    PointerDeviceKind.touch,
  );

  void _updateScale(double scale) {
    setState(() {
      _scale = scale;
    });
    widget.onScaleChanged?.call(1 / scale);
  }

  void _updateLastScale(double scale) {
    setState(() {
      _lastScale = scale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        double height = constraints.maxHeight;
        double width = constraints.maxWidth;
        //The listener is needed to determine the input type
        //and for forceHoldOnPointerDown and for reseting the DragMode.
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerUp: (PointerUpEvent event) {
            _dragMode = DragMode.none;
          },
          onPointerDown: widget.forceHoldOnPointerDown
              ? (_) {
                  if (widget.forceHoldOnPointerDown) {
                    _verticalController.position.hold(() {});
                    _horizontalController.position.hold(() {});
                  }
                }
              : null,
          onPointerPanZoomStart: widget.forceHoldOnPointerDown
              ? (_) {
                  _verticalController.position.hold(() {});
                  _horizontalController.position.hold(() {});
                }
              : null,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onScaleStart: (ScaleStartDetails details) {
              _clearScaleAnimationListeners();
              _masterAnimationController.stop();
              _trackPadState = details.kind == PointerDeviceKind.trackpad
                  ? TrackPadState.waiting
                  : TrackPadState.none;
              if (details.pointerCount == 1) {
                DragStartDetails dragDetails = DragStartDetails(
                  globalPosition: details.focalPoint,
                  kind: PointerDeviceKind.touch,
                );
                _verticalTouchHandler.handleDragStart(dragDetails);
                _horizontalTouchHandler.handleDragStart(dragDetails);
              }
            },
            onScaleUpdate: (ScaleUpdateDetails details) {
              if (_dragMode == DragMode.none) {
                if (_trackPadState == TrackPadState.waiting) {
                  if (details.scale != 1.0) {
                    if (widget.pinchEnabled) {
                      _trackPadState = TrackPadState.scale;
                      _dragMode = DragMode.pinchScale;
                    }
                  } else {
                    _globalTrackpadDistance += details.focalPointDelta * _scale;
                    if (_globalTrackpadDistance.longestSide > kPrecisePointerPanSlop) {
                      _trackPadState = TrackPadState.pan;
                      _dragMode = DragMode.pan;
                      DragStartDetails dragDetails = DragStartDetails(
                        globalPosition: details.focalPoint,
                        kind: PointerDeviceKind.touch,
                      );
                      _verticalTouchHandler.handleDragStart(dragDetails);
                      _horizontalTouchHandler.handleDragStart(dragDetails);
                    }
                  }
                } else if (details.pointerCount > 1) {
                  if (widget.pinchEnabled) {
                    _dragMode = DragMode.pinchScale;
                  }
                } else {
                  _dragMode = DragMode.pan;
                }
              }
              switch (_dragMode) {
                case DragMode.doubleTapDrag:
                  final currentDragPosition = details.localFocalPoint;
                  final double dx = (_previousDragPosition!.dx - currentDragPosition.dx);
                  double dy = (_previousDragPosition!.dy - currentDragPosition.dy);

                  if (dx.abs() > dy.abs()) {
                    // Ignore horizontal drags
                    return;
                  }
                  final newScale = _clampDouble(
                    //divided by 2 so that dragging from the middle of the screen
                    //to the bottom results in 2x scale
                    _lastScale + (dy / (height / 2)),
                    _minInternalScale,
                    _maxInternalScale,
                  );
                  final verticalOffset = _clampScrollTarget(
                    axis: Axis.vertical,
                    scrollAxis: widget.scrollAxis,
                    controller: _verticalController,
                    rawCrossDimension: height,
                    newInternalScale: newScale,
                    value: _verticalController.position.pixels +
                        (_scale - newScale) *
                            _mainAxisFocalCoord(
                              raw: details.localFocalPoint.dy,
                              dimension: height,
                              axis: Axis.vertical,
                              scrollAxis: widget.scrollAxis,
                              reverse: widget.reverse,
                            ),
                  );
                  final horizontalOffset = _clampScrollTarget(
                    axis: Axis.horizontal,
                    scrollAxis: widget.scrollAxis,
                    controller: _horizontalController,
                    rawCrossDimension: width,
                    newInternalScale: newScale,
                    value: _horizontalController.position.pixels +
                        (_scale - newScale) *
                            _mainAxisFocalCoord(
                              raw: details.localFocalPoint.dx,
                              dimension: width,
                              axis: Axis.horizontal,
                              scrollAxis: widget.scrollAxis,
                              reverse: widget.reverse,
                            ),
                  );

                  _updateScale(newScale);

                  _verticalController.jumpTo(verticalOffset);
                  _horizontalController.jumpTo(horizontalOffset);
                case DragMode.pan:
                  final correctedDelta = details.focalPointDelta * _scale;
                  final correctedOffset = details.focalPoint * _scale;
                  final time = details.sourceTimeStamp!;
                  _tracker.addPosition(time, correctedOffset);
                  final DragUpdateDetails verticalDetails = DragUpdateDetails(
                    globalPosition: correctedOffset,
                    sourceTimeStamp: time,
                    primaryDelta: correctedDelta.dy,
                    delta: Offset(0.0, correctedDelta.dy),
                  );
                  final DragUpdateDetails horizontalDetails = DragUpdateDetails(
                    globalPosition: correctedOffset,
                    sourceTimeStamp: time,
                    primaryDelta: correctedDelta.dx,
                    delta: Offset(correctedDelta.dx, 0.0),
                  );
                  _verticalTouchHandler.handleDragUpdate(verticalDetails);
                  _horizontalTouchHandler.handleDragUpdate(horizontalDetails);
                case DragMode.pinchScale:
                  // Honour a live pinch-off even if the gesture was already in
                  // pinch mode when the setting flipped.
                  if (!widget.pinchEnabled) {
                    _dragMode = DragMode.none;
                    break;
                  }
                  final newScale = _clampDouble(
                    _lastScale / details.scale,
                    _minInternalScale,
                    _maxInternalScale,
                  );
                  // Live focal point, not the one captured at onScaleStart: a
                  // pinch's midpoint drifts as the two fingers move (rarely
                  // perfectly static), and onScaleStart itself fires off
                  // whichever finger touches down FIRST — Flutter doesn't
                  // restart the gesture when the second one joins — so a
                  // frozen point anchors the zoom whenever the fingers'
                  // midpoint moves from where the first finger happened to
                  // land, rather than the actual pinch center (#372). Also
                  // clamped to what's actually scrollable right now: near a
                  // content edge, jumpTo would otherwise accept an offset
                  // beyond the available range and let Flutter's own,
                  // unrelated-to-the-focal-point correction snap it back on
                  // a later frame (#372).
                  final verticalOffset = _clampScrollTarget(
                    axis: Axis.vertical,
                    scrollAxis: widget.scrollAxis,
                    controller: _verticalController,
                    rawCrossDimension: height,
                    newInternalScale: newScale,
                    value: _verticalController.position.pixels +
                        (_scale - newScale) *
                            _mainAxisFocalCoord(
                              raw: details.localFocalPoint.dy,
                              dimension: height,
                              axis: Axis.vertical,
                              scrollAxis: widget.scrollAxis,
                              reverse: widget.reverse,
                            ),
                  );
                  final horizontalOffset = _clampScrollTarget(
                    axis: Axis.horizontal,
                    scrollAxis: widget.scrollAxis,
                    controller: _horizontalController,
                    rawCrossDimension: width,
                    newInternalScale: newScale,
                    value: _horizontalController.position.pixels +
                        (_scale - newScale) *
                            _mainAxisFocalCoord(
                              raw: details.localFocalPoint.dx,
                              dimension: width,
                              axis: Axis.horizontal,
                              scrollAxis: widget.scrollAxis,
                              reverse: widget.reverse,
                            ),
                  );
                  //This is the main logic to actually perform the scaling
                  _updateScale(newScale);
                  _verticalController.jumpTo(verticalOffset);
                  _horizontalController.jumpTo(horizontalOffset);
                case DragMode.none:
                // do nothing
              }
            },
            onScaleEnd: (ScaleEndDetails details) {
              _trackPadState = TrackPadState.none;
              _globalTrackpadDistance = Size.zero;
              _lastScale = _scale;
              _previousDragPosition = null;

              Offset velocity = _tracker.getVelocity().pixelsPerSecond;
              DragEndDetails endDetails = DragEndDetails(
                velocity: Velocity(pixelsPerSecond: Offset(0.0, velocity.dy)),
                primaryVelocity: velocity.dy,
              );
              DragEndDetails hEndDetails = DragEndDetails(
                velocity: Velocity(pixelsPerSecond: Offset(velocity.dx, 0.0)),
                primaryVelocity: velocity.dx,
              );
              _verticalTouchHandler.handleDragEnd(endDetails);
              _horizontalTouchHandler.handleDragEnd(hEndDetails);
              widget.onScaleEnd?.call(
                ZoomViewScaleEndDetails(
                  pointerCount: details.pointerCount,
                  scale: 1 / _scale,
                ),
              );
              _dragMode = DragMode.none;
            },
            onDoubleTapDown: widget.onDoubleTap == null && widget.doubleTapDrag == false
                ? null
                : (TapDownDetails details) {
                    if (widget.doubleTapDrag) {
                      _dragMode = DragMode.doubleTapDrag;
                      _previousDragPosition = details.localPosition;
                    }
                    _tapDownDetails = details;
                  },
            onDoubleTap: widget.onDoubleTap == null
                ? null
                : () {
                    widget.onDoubleTap!(_tapDownDetails);
                  },
            child: Column(
              children: [
                Expanded(
                  //When scale decreases, the SizedBox will shrink and the FittedBox
                  //will scale the child to fit the maximum constraints of the ZoomView
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox(
                      height: height * _scale,
                      width: width * _scale,
                      child: Center(
                        child: ScrollConfiguration(
                          behavior: const ScrollBehavior().copyWith(
                            overscroll: false,
                            //Disable all inputs on the list as we will handle them
                            //ourselves using the gesture detector and scroll controllers
                            dragDevices: <PointerDeviceKind>{},
                            scrollbars: false,
                          ),
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            controller: widget.scrollAxis == Axis.vertical
                                ? _horizontalController
                                : _verticalController,
                            scrollDirection: widget.scrollAxis == Axis.vertical
                                ? Axis.horizontal
                                : Axis.vertical,
                            child: SizedBox(
                              width: widget.scrollAxis == Axis.vertical ? width : null,
                              height: widget.scrollAxis == Axis.vertical ? null : height,
                              child: widget.child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// keeps record of the state of a trackpad. Should be set to none if
/// the PointerDeviceKind is not a trackpad
enum TrackPadState { none, waiting, pan, scale }

/// Handles the logic for a double tap zoom.
/// This should be used with the [ZoomView.onDoubleTap] callback.
final class ZoomViewGestureHandler {
  int _index = 0;
  final List<double> zoomLevels;
  final Duration duration;
  final ZoomViewController controller;

  /// Creates a handler for double tap gestures.
  ///
  /// [controller] is the [ZoomViewController] that this handler will control.
  /// [zoomLevels] is a list of zoom scales to cycle through on each double tap.
  /// [duration] is the animation duration for the zoom.
  ZoomViewGestureHandler({
    required this.controller,
    required this.zoomLevels,
    this.duration = const Duration(milliseconds: 150),
  });

  /// The method to be passed to [ZoomView.onDoubleTap].
  void onDoubleTap(TapDownDetails details) {
    if (!controller.isAttached) return;

    final currentScale = controller.scale;
    late double newScale;

    if (currentScale < 1.0) {
      newScale = 1.0;
      _index = 0;
    } else {
      newScale = zoomLevels[_index];
      _index++;
      if (_index >= zoomLevels.length) {
        _index = 0;
      }
    }

    final focalPoint = details.localPosition;

    if (duration > Duration.zero) {
      controller.setScaleWithAnimation(
        newScale,
        duration: duration,
        focalPoint: focalPoint,
      );
    } else {
      controller.setScale(newScale, focalPoint: focalPoint);
    }
  }
}

/// Touch handlers copied from Flutter ScrollableState
final class _TouchHandler {
  final ScrollController controller;
  _TouchHandler({required this.controller});
  Drag? _drag;
  ScrollHoldController? _hold;

  void handleDragDown(DragDownDetails details) {
    assert(_drag == null);
    assert(_hold == null);
    _hold = controller.position.hold(disposeHold);
  }

  void handleDragStart(DragStartDetails details) {
    assert(_drag == null);
    _drag = controller.position.drag(details, disposeDrag);
    assert(_drag != null);
    assert(_hold == null);
  }

  void handleDragUpdate(DragUpdateDetails details) {
    assert(_hold == null || _drag == null);
    _drag?.update(details);
  }

  void handleDragEnd(DragEndDetails details) {
    assert(_hold == null || _drag == null);
    _drag?.end(details);
    assert(_drag == null);
  }

  void handleDragCancel() {
    assert(_hold == null || _drag == null);
    _hold?.cancel();
    _drag?.cancel();
    assert(_hold == null);
    assert(_drag == null);
  }

  void disposeHold() {
    _hold = null;
  }

  void disposeDrag() {
    _drag = null;
  }
}

double _clampDouble(double x, double min, double max) {
  if (x < min) {
    return min;
  }
  if (x > max) {
    return max;
  }
  return x;
}

/// Clamps a computed scroll target to what [controller] can actually scroll
/// to right now, so a zoom step near a content edge can't request an offset
/// beyond the available range. Without this, `jumpTo` would still accept the
/// out-of-range value (it forces `pixels` directly, no clamping), and
/// Flutter's own scroll-position correction only snaps it back on a later
/// layout pass — with no regard for the focal point the zoom was trying to
/// keep in place. That delayed, uncontrolled correction is what let a zoom
/// near a top/bottom (or left/right) edge drift the tapped/pinched content
/// out from under the finger instead of staying put (#372).
double _clampToScrollExtent(ScrollController controller, double value) {
  final position = controller.position;
  return _clampDouble(value, position.minScrollExtent, position.maxScrollExtent);
}

/// Clamps a computed scroll target for the controller bound to [axis]
/// (Axis.horizontal or Axis.vertical — i.e. which physical direction, not
/// which reader mode) to what will actually be scrollable once
/// [newInternalScale] takes effect.
///
/// The MAIN axis (the one equal to [scrollAxis]) keeps using
/// [_clampToScrollExtent]: its scroll range comes from `widget.child`'s own
/// content, which ZoomView has no way to compute analytically.
///
/// The CROSS axis (perpendicular to [scrollAxis]) is different: it's
/// ZoomView's own synthetic pan, and its scrollable range is pure geometry —
/// [rawCrossDimension] (the fixed, unscaled viewport size on that axis)
/// minus the viewport that axis actually gets once zoomed
/// (`rawCrossDimension * newInternalScale`; see `_effectivePixels`'s doc for
/// why that's the viewport size). Every caller here computes this target
/// and calls `_updateScale` practically back-to-back, and `_updateScale`'s
/// `setState()` does not re-layout synchronously — so reading the cross
/// axis's `ScrollPosition.maxScrollExtent` at this point still reflects the
/// PREVIOUS frame's scale, not the one about to apply. That staleness is
/// harmless for the main axis, whose range is normally far larger than one
/// animation step could cross, but the cross axis starts at EXACTLY zero
/// range at 1x and must grow from there the instant a zoom-in begins.
/// Clamping that first frame's target against the stale (zero) extent
/// stalls it at zero — and because every caller here tracks a running
/// position across frames rather than recomputing an absolute one each
/// time, every later frame's delta then compounds on that wrong baseline
/// instead of the right one, producing a large, persistent drift on
/// whichever screen axis ISN'T scrollAxis (reported: pinch/double-tap zoom
/// not staying anchored to the touched point, worse in horizontal mode).
double _clampScrollTarget({
  required Axis axis,
  required Axis scrollAxis,
  required ScrollController controller,
  required double rawCrossDimension,
  required double newInternalScale,
  required double value,
}) {
  if (axis == scrollAxis) {
    return _clampToScrollExtent(controller, value);
  }
  final maxExtent = newInternalScale >= 1.0
      ? 0.0
      : rawCrossDimension * (1.0 - newInternalScale);
  return _clampDouble(value, 0.0, maxExtent);
}

/// The controller for the axis perpendicular to [scrollAxis] is a local,
/// synthetic [ScrollController] that sits at pixel 0 until the user pans it,
/// even though the [FittedBox]/[SizedBox] around it already centers the
/// enlarged content on that axis once zoomed past 1x — so a fresh zoom step
/// must treat that axis's "current" offset as the centering offset, not the
/// stale raw scroll position. The controller for [scrollAxis] itself is the
/// real scrollable (e.g. the reader's page/strip position) and must always
/// use its actual pixels: overriding it with the centering formula would
/// discard wherever the user had actually scrolled to.
({double horizontal, double vertical}) _effectivePixels({
  required Axis scrollAxis,
  required double currentInternalScale,
  required double width,
  required double height,
  required ScrollController horizontalController,
  required ScrollController verticalController,
}) {
  if (scrollAxis == Axis.vertical) {
    final horizontal = currentInternalScale > 1.0
        ? -(width * currentInternalScale - width) / 2.0
        : horizontalController.position.pixels;
    return (horizontal: horizontal, vertical: verticalController.position.pixels);
  } else {
    final vertical = currentInternalScale > 1.0
        ? -(height * currentInternalScale - height) / 2.0
        : verticalController.position.pixels;
    return (horizontal: horizontalController.position.pixels, vertical: vertical);
  }
}

/// The focal-point coordinate on [axis] to actually use in every
/// recentering formula below, correcting for [reverse].
///
/// Every formula in this file is built from terms like
/// `pixels + delta * focus.dx`, which assumes increasing `pixels` moves
/// content in the same screen direction as increasing screen coordinates.
/// That holds for the MAIN axis (the one equal to [scrollAxis]) only when
/// the wrapped scrollable is NOT reversed — Flutter paints a reversed
/// sliver's `AxisDirection` by measuring from the OPPOSITE physical edge of
/// the viewport, i.e. (conceptually) `screenPos = dimension - (pixels-relative
/// position)` instead of `screenPos = (pixels-relative position)`. Naively
/// negating the whole delta term does NOT correct for this — it's a
/// reflection of the coordinate around the viewport's own extent, not a
/// sign flip of the delta — verified against the actual `RenderSliverList`
/// paint offsets by direct measurement (see the zoom-view-reverse
/// investigation notes): reversed, `pixels` increasing by N moves a fixed
/// content point by +N on screen (not -N as non-reversed does), AND the
/// reversed formula carries an extra `+dimension` term that does not scale
/// with zoom the way the rest of the expression does. Reflecting the focal
/// coordinate itself (`dimension - raw`) before it enters the existing
/// (already-correct-for-non-reverse) formula reproduces the right target in
/// both cases without duplicating the formula.
///
/// [dimension] is the full unscaled viewport size along [axis] (`width` for
/// horizontal, `height` for vertical). The cross axis is ZoomView's own
/// synthetic pan controller, never the wrapped (possibly reversed) list, so
/// [reverse] never applies there — [raw] passes through unchanged.
double _mainAxisFocalCoord({
  required double raw,
  required double dimension,
  required Axis axis,
  required Axis scrollAxis,
  required bool reverse,
}) =>
    (reverse && axis == scrollAxis) ? dimension - raw : raw;
