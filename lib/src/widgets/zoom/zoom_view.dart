// Vendored zoom_view v1.0.2: https://github.com/yakagami/zoom_view
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

class ZoomViewController {
  _ZoomViewState? _state;

  void _attach(_ZoomViewState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  bool get isAttached => _state != null;

  double get scale {
    if (!isAttached) return 1.0;
    return 1 / _state!._scale;
  }

  /// After onScaleEnd, retains the last gesture mode.
  DragMode get dragMode {
    if (!isAttached) {
      throw ("Controler is not attached to a ZoomView");
    }
    return _state!._dragMode;
  }

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

    // Detach listeners from interrupted animations before starting another.
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
        // Skip the duplicate first tick so viewport geometry can settle.
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

class ZoomListView extends StatefulWidget {
  final ListView child;
  final double minScale;
  final double maxScale;

  final bool doubleTapDrag;

  final bool doubleTapZoom;

  final ValueChanged<double>? onScaleChanged;

  /// Created internally when omitted.
  final ZoomViewController? zoomViewController;

  /// Defaults to zooming to min(maxScale, 3.0) when doubleTapZoom is enabled.
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

final class ZoomViewScaleEndDetails {
  final int pointerCount;

  final double scale;

  ZoomViewScaleEndDetails({
    required this.pointerCount,
    required this.scale,
  });
}

/// Requires a ScrollPosition and jumpTo-capable controller on the wrapped scrollable.
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

  final void Function(TapDownDetails details)? onDoubleTap;
  final Widget child;
  final ScrollController controller;

  final ZoomViewController? zoomViewController;

  /// Must match the wrapped scrollable axis.
  final Axis scrollAxis;

  /// Must match wrapped reverse; mirror focal coordinates only on scrollAxis, never the synthetic cross axis.
  final bool reverse;

  /// double.infinity allows unlimited zoom in.
  final double maxScale;

  /// Zero allows unlimited zoom out.
  final double minScale;

  final bool doubleTapDrag;

  /// Stop flings on pointer down when the scale recognizer may not win the arena.
  final bool forceHoldOnPointerDown;

  /// Disabling pinch resets to 1x; double-tap zoom remains available.
  final bool pinchEnabled;

  final void Function(double scale)? onScaleChanged;

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
    // Defer the pinch-off reset until layout supplies context.size.
    if (oldWidget.pinchEnabled && !widget.pinchEnabled && _scale != 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resetScaleToOne();
      });
    }
  }

  void _resetScaleToOne() {
    final size = context.size;
    if (size == null) return;
    // Mode transitions may briefly detach a controller; check both before reading pixels.
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

  double _scale = 1;

  double _lastScale = 1;

  late TrackPadState _trackPadState;

  Size _globalTrackpadDistance = Size.zero;

  late final AnimationController _masterAnimationController;

  // Stopped animations never complete; track listeners so interruptions can detach them.
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

  // Internal scale is 1/userScale, so user min/max map to internal max/min.
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
                    return;
                  }
                  final newScale = _clampDouble(
                    // A drag from screen center to bottom represents 2x scale.
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
                  if (!widget.pinchEnabled) {
                    _dragMode = DragMode.none;
                    break;
                  }
                  final newScale = _clampDouble(
                    _lastScale / details.scale,
                    _minInternalScale,
                    _maxInternalScale,
                  );
                  // onScaleStart uses the first finger; live focal points track the actual pinch midpoint.
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
                case DragMode.none:
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
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox(
                      height: height * _scale,
                      width: width * _scale,
                      child: Center(
                        child: ScrollConfiguration(
                          behavior: const ScrollBehavior().copyWith(
                            overscroll: false,
                            // The gesture detector owns input; disable competing scrollable drag recognizers.
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

/// Use none for non-trackpad input.
enum TrackPadState { none, waiting, pan, scale }

final class ZoomViewGestureHandler {
  int _index = 0;
  final List<double> zoomLevels;
  final Duration duration;
  final ZoomViewController controller;

  /// Cycle zoomLevels on each double tap.
  ZoomViewGestureHandler({
    required this.controller,
    required this.zoomLevels,
    this.duration = const Duration(milliseconds: 150),
  });

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

/// jumpTo does not clamp; constrain targets before applying focal-point zoom.
double _clampToScrollExtent(ScrollController controller, double value) {
  final position = controller.position;
  return _clampDouble(value, position.minScrollExtent, position.maxScrollExtent);
}

/// Compute cross-axis bounds at the new scale; ScrollPosition still reports the previous frame's extent.
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

/// Below 1x, synthetic cross-axis pixels must include centering; main-axis pixels retain reader position.
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

/// Reflect focal coordinates as dimension-raw only on the reversed main axis; negating the delta is insufficient.
double _mainAxisFocalCoord({
  required double raw,
  required double dimension,
  required Axis axis,
  required Axis scrollAxis,
  required bool reverse,
}) =>
    (reverse && axis == scrollAxis) ? dimension - raw : raw;
