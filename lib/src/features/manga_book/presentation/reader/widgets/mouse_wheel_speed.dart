// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../../utils/motion/reduce_motion.dart';
import '../utils/wheel_scroll.dart';

/// Register above the scrollable so the first-wins signal resolver suppresses its jump; leave trackpads unchanged.
class MouseWheelSpeed extends StatefulWidget {
  const MouseWheelSpeed({
    super.key,
    required this.speed,
    required this.axis,
    required this.reverse,
    required this.positionOf,
    required this.child,
  });

  final double speed;
  final Axis axis;
  final bool reverse;

  /// Resolved late: the reader's scroll position outlives individual builds.
  final ScrollPosition? Function() positionOf;

  final Widget child;

  @override
  State<MouseWheelSpeed> createState() => _MouseWheelSpeedState();
}

class _MouseWheelSpeedState extends State<MouseWheelSpeed>
    with TickerProviderStateMixin {
  /// Exponential smoothing time constant; one notch settles in roughly 150..200ms.
  static const _tau = 0.06;
  static const _settleDistance = 0.5;

  /// Accumulate new notches at the target so unfinished travel is not lost.
  double? _pendingTarget;
  ScrollPosition? _pendingOn;
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  /// Ticker's first frame reports zero elapsed; count it as one frame so the
  /// first wheel event is not held back.
  bool _primed = false;

  /// Guard follower jumps so their notifications cannot be mistaken for user takeover.
  bool _applying = false;

  /// Cached in [didChangeDependencies] because [ScrollConfiguration.of]
  /// registers an inherited dependency, which belongs in the lifecycle.
  ScrollBehavior? _behavior;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _behavior = ScrollConfiguration.of(context);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Anything that scrolls the strip without going through the follower (drag,
    // fling, auto scroll, keyboard) stops it, so the two never fight.
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      // Stack hit-tests the last child first; register above the strip to win wheel resolution.
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerSignal: _onPointerSignal,
            ),
          ),
        ],
      ),
    );
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (_applying || _pendingTarget == null || _pendingOn == null) return false;
    final owned = _pendingOn!.context.notificationContext;
    if (notification is ScrollStartNotification &&
        notification.context == owned) {
      _stopFollower();
    }
    return false;
  }

  /// Match Scrollable axis modifiers (scrollable.dart:933-951); do not flip trackpad axes.
  double _axisDelta(PointerScrollEvent event) {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final flipAxes =
        pressed.any(
          (_behavior ?? const ScrollBehavior()).pointerAxisModifiers.contains,
        ) &&
        event.kind == PointerDeviceKind.mouse;
    final axis = flipAxes ? flipAxis(widget.axis) : widget.axis;
    return axis == Axis.horizontal
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
  }

  double? _targetFor(ScrollPosition position, PointerScrollEvent event) {
    return wheelScrollTarget(
      pixels: position.pixels,
      pendingTarget: identical(_pendingOn, position) ? _pendingTarget : null,
      rawDelta: _axisDelta(event),
      reverse: widget.reverse,
      speed: widget.speed,
      minExtent: position.minScrollExtent,
      maxExtent: position.maxScrollExtent,
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (event.kind != PointerDeviceKind.mouse) return;
    final position = widget.positionOf();
    if (position == null || !position.hasPixels) return;
    // Scrollable only registers when the event would move it. Doing the same
    // leaves an event we can't use, such as Shift + vertical wheel on a
    // vertical strip, to the platform's own handling instead of swallowing it.
    if (_targetFor(position, event) == null) return;
    GestureBinding.instance.pointerSignalResolver.register(event, _glideTo);
  }

  void _glideTo(PointerEvent event) {
    if (event is! PointerScrollEvent) return;
    final position = widget.positionOf();
    if (position == null || !position.hasPixels) return;

    if (_pendingOn != position) {
      _ticker?.stop();
      _pendingTarget = null;
      _pendingOn = position;
    }
    final target = _targetFor(position, event);
    if (target == null) {
      // A notch can cancel the follow exactly, or push against an end. The
      // event was registered before this check, so leave it unhandled.
      _stopFollower();
      return;
    }
    _pendingTarget = target;
    event.respond(allowPlatformDefault: false);

    if (!mounted) return;
    // Report user scrolling for glides and reduced-motion jumps so auto-scroll yields.
    _notifyUserScroll(position, target);
    if (context.reduceMotion) {
      _stopFollower();
      position.jumpTo(target);
      return;
    }

    if (_ticker!.isTicking) return;
    _lastTick = Duration.zero;
    _primed = false;
    _ticker!.start();
  }

  void _notifyUserScroll(ScrollPosition position, double target) {
    final notificationContext = position.context.notificationContext;
    if (notificationContext == null) return;
    UserScrollNotification(
      metrics: position.copyWith(),
      context: notificationContext,
      direction: target < position.pixels
          ? ScrollDirection.forward
          : ScrollDirection.reverse,
    ).dispatch(notificationContext);
  }

  void _tick(Duration elapsed) {
    final position = _pendingOn;
    if (position == null ||
        _pendingTarget == null ||
        !position.hasPixels ||
        !identical(widget.positionOf(), position)) {
      _stopFollower();
      return;
    }

    final dt = _primed
        ? math.min(
            (elapsed - _lastTick).inMicroseconds /
                Duration.microsecondsPerSecond,
            0.1,
          )
        : 1 / 60;
    _primed = true;
    _lastTick = elapsed;

    // Chapter loads can grow the extents while the follow is running.
    final target = _pendingTarget!
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _pendingTarget = target;

    final pixels = position.pixels;
    if ((target - pixels).abs() <= _settleDistance) {
      _apply(position, target);
      _stopFollower();
      return;
    }
    _apply(position, pixels + (target - pixels) * (1 - math.exp(-dt / _tau)));
  }

  /// Dispatch ordinary scroll notifications for each jump, guarded against stopping the follower itself.
  void _apply(ScrollPosition position, double pixels) {
    if (position.pixels == pixels) return;
    _applying = true;
    try {
      position.jumpTo(pixels);
    } finally {
      _applying = false;
    }
  }

  void _stopFollower() {
    _ticker?.stop();
    _pendingTarget = null;
    _pendingOn = null;
  }
}
