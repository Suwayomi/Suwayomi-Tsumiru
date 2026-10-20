// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../../../../utils/motion/reduce_motion.dart';
import '../utils/wheel_scroll.dart';

/// Glides mouse wheel scrolling inside [child] by [speed].
///
/// A wheel notch moves 53px on desktop, which reads slower than the browser the
/// WebUI runs in. Trackpads already send fine-grained deltas, so only a mouse is
/// touched — the same distinction WebUI makes before it remaps wheel input.
///
/// Flutter's [Scrollable] would otherwise jump straight to the notch target,
/// which a notched wheel shows as a staircase. Registering the event with the
/// pointer signal resolver from a sibling painted on top means ours is the
/// first registration of the hit test and the Scrollable's own jump is dropped
/// (`pointer_signal_resolver.dart`: the first registered callback wins).
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

class _MouseWheelSpeedState extends State<MouseWheelSpeed> {
  static const _glideDuration = Duration(milliseconds: 150);

  /// Where the running glide is headed. A notch arriving before it lands
  /// extends this instead of closing the gap the animation still has to cover.
  double? _pendingTarget;
  ScrollPosition? _pendingOn;
  int _glide = 0;

  @override
  Widget build(BuildContext context) {
    // The listener must be the first hit in the tree for the resolver to give
    // it the event: a Stack tests its last child first, so it sits above the
    // strip without taking any pointer events from it.
    return Stack(
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
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (event.kind != PointerDeviceKind.mouse) return;
    final position = widget.positionOf();
    if (position == null || !position.hasPixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, _glideTo);
  }

  void _glideTo(PointerEvent event) {
    if (event is! PointerScrollEvent) return;
    final position = widget.positionOf();
    if (position == null || !position.hasPixels) return;
    event.respond(allowPlatformDefault: false);

    if (_pendingOn != position) {
      _pendingTarget = null;
      _pendingOn = position;
    }
    final target = wheelScrollTarget(
      pixels: position.pixels,
      pendingTarget: _pendingTarget,
      rawDelta: widget.axis == Axis.vertical
          ? event.scrollDelta.dy
          : event.scrollDelta.dx,
      reverse: widget.reverse,
      speed: widget.speed,
      minExtent: position.minScrollExtent,
      maxExtent: position.maxScrollExtent,
    );
    if (target == null) {
      // A notch can cancel an in-flight glide exactly; stop where it is now.
      if (_pendingTarget != null) {
        _pendingTarget = null;
        _glide++;
        position.jumpTo(position.pixels);
      }
      return;
    }
    _pendingTarget = target;

    if (!mounted) return;
    if (context.reduceMotion) {
      _pendingTarget = null;
      position.jumpTo(target);
      return;
    }

    // A glide is user scrolling: auto scroll yields to it the same way it does
    // to the platform's own wheel jump, which reports a direction change.
    final notificationContext = position.context.notificationContext;
    if (notificationContext != null) {
      UserScrollNotification(
        metrics: position.copyWith(),
        context: notificationContext,
        direction: target < position.pixels
            ? ScrollDirection.forward
            : ScrollDirection.reverse,
      ).dispatch(notificationContext);
    }

    final glide = ++_glide;
    position
        .animateTo(
          target,
          duration: _glideDuration,
          curve: Curves.decelerate,
        )
        .whenComplete(() {
          if (glide == _glide) _pendingTarget = null;
        });
  }
}
