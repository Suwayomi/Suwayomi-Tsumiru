// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/wheel_scroll.dart';

/// Scales mouse wheel scrolling inside [child] by [speed].
///
/// A wheel notch moves 53px on desktop, which reads slower than the browser the
/// WebUI runs in. Trackpads already send fine-grained deltas, so only a mouse is
/// scaled — the same call WebUI makes before it remaps wheel input.
class MouseWheelSpeed extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (speed == 1) return child;
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        if (event.kind != PointerDeviceKind.mouse) return;
        final position = positionOf();
        if (position == null || !position.hasPixels) return;
        final target = wheelScrollTarget(
          pixels: position.pixels,
          rawDelta:
              axis == Axis.vertical ? event.scrollDelta.dy : event.scrollDelta.dx,
          reverse: reverse,
          speed: speed,
          minExtent: position.minScrollExtent,
          maxExtent: position.maxScrollExtent,
        );
        if (target == null) return;
        // Land on the absolute target after Flutter has applied its own delta
        // this dispatch. Adding a relative amount first gets clamped on its own
        // and overshoots near either end.
        scheduleMicrotask(() {
          if (!context.mounted) return;
          final live = positionOf();
          if (live == null || !live.hasPixels || live.pixels == target) return;
          live.jumpTo(target);
        });
      },
      child: child,
    );
  }
}
