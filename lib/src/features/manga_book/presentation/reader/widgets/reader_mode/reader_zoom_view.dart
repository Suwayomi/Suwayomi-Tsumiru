// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../../../widgets/zoom/zoom_view.dart';

/// The reader's [ZoomView] wrapper, controlling pinch and double-tap zoom
/// independently.
///
/// [pinchEnabled] toggles the two-finger pinch (resetting to 1x when off);
/// [doubleTapToZoom] adds a double-tap that toggles 1x <-> ~3x at the tapped
/// point. Either being on keeps this mounted. [minScale] / [maxScale] apply
/// live, so "disable zoom out" needs no reader restart. The [ZoomViewController]
/// survives rebuilds ([useMemoized]) to stay attached across the reader's
/// frequent rebuilds.
class ReaderZoomView extends HookWidget {
  const ReaderZoomView({
    super.key,
    required this.controller,
    required this.scrollAxis,
    required this.maxScale,
    required this.minScale,
    required this.pinchEnabled,
    required this.doubleTapToZoom,
    required this.child,
  });

  final ScrollController controller;
  final Axis scrollAxis;
  final double maxScale;
  final double minScale;
  final bool pinchEnabled;
  final bool doubleTapToZoom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final zoomController = useMemoized(ZoomViewController.new);
    // Cap the zoomed-in target at the mode's max scale.
    final zoomInTarget = maxScale < 3.0 ? maxScale : 3.0;
    // Stateless toggle: zoom out if we're zoomed in at all, otherwise zoom in
    // at the tapped point. Reading the live scale each time (instead of a
    // cycling index) can't desync from a dropped tap or a pinch in between.
    void onDoubleTap(TapDownDetails details) {
      if (!zoomController.isAttached) return;
      final target = zoomController.scale > 1.01 ? 1.0 : zoomInTarget;
      zoomController.setScaleWithAnimation(
        target,
        focalPoint: details.localPosition,
      );
    }

    return ZoomView(
      controller: controller,
      zoomViewController: zoomController,
      scrollAxis: scrollAxis,
      maxScale: maxScale,
      minScale: minScale,
      pinchEnabled: pinchEnabled,
      onDoubleTap: doubleTapToZoom ? onDoubleTap : null,
      // Required so the scale recognizer wins the gesture arena against the
      // underlying scrollable's pan recognizer (closes #256).
      forceHoldOnPointerDown: true,
      child: child,
    );
  }
}
