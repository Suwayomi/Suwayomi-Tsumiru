// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../widgets/zoom/zoom_view.dart';

class ReaderZoomView extends HookWidget {
  const ReaderZoomView({
    super.key,
    required this.controller,
    required this.scrollAxis,
    this.reverse = false,
    required this.maxScale,
    required this.minScale,
    required this.pinchEnabled,
    required this.doubleTapToZoom,
    this.onScaleChanged,
    required this.child,
  });

  final ScrollController controller;
  final Axis scrollAxis;

  /// Must match the wrapped scrollable's own `reverse` (e.g. an RTL manga's
  /// continuous-horizontal strip) — see [ZoomView.reverse] for why.
  final bool reverse;
  final double maxScale;
  final double minScale;
  final bool pinchEnabled;
  final bool doubleTapToZoom;

  /// Invoked with the live user-facing scale (1.0 = unzoomed) any time it
  /// changes, e.g. so callers can yield competing single-finger gestures
  /// (chapter-swipe) while the reader is zoomed in.
  final ValueChanged<double>? onScaleChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final zoomController = useMemoized(ZoomViewController.new);
    final zoomInTarget = maxScale < 3.0 ? maxScale : 3.0;
    // Read live scale for each double tap so intervening pinches cannot desynchronise the toggle.
    void onDoubleTap(TapDownDetails details) {
      if (!zoomController.isAttached) return;
      final target = zoomController.scale > 1.01 ? 1.0 : zoomInTarget;
      zoomController.setScaleWithAnimation(
        target,
        duration: context.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 150),
        focalPoint: details.localPosition,
      );
    }

    return ZoomView(
      controller: controller,
      zoomViewController: zoomController,
      scrollAxis: scrollAxis,
      reverse: reverse,
      maxScale: maxScale,
      minScale: minScale,
      pinchEnabled: pinchEnabled,
      onDoubleTap: doubleTapToZoom ? onDoubleTap : null,
      onScaleChanged: onScaleChanged,
      // Hold the scrollable so the scale recognizer can win its gesture arena.
      forceHoldOnPointerDown: true,
      child: child,
    );
  }
}
