// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Tests for the pinch-to-zoom wiring used by the reader modes.
//
// Background: ZoomView is wrapped around a ScrollablePositionedList (or a
// PageView in the single-page case) and is supposed to capture two-finger
// scale gestures. Without `forceHoldOnPointerDown: true`, the underlying
// scrollable's pan recognizer wins the gesture arena and `ZoomView` never
// sees the scale start — pinch does literally nothing on device. These
// tests pin both behaviours: the scale callback fires when forceHold is
// on, and the single-finger scroll path still works regardless.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:tsumiru/src/widgets/zoom/scroll_offset_to_scroll_controller.dart';
import 'package:tsumiru/src/widgets/zoom/zoom_view.dart';

const double _viewportWidth = 400.0;
const double _viewportHeight = 800.0;
const double _itemHeight = 200.0;

Future<void> _pumpZoomWrappedList(
  WidgetTester tester, {
  required bool forceHoldOnPointerDown,
  required void Function(double scale) onScaleChanged,
  bool pinchEnabled = true,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(_viewportWidth, _viewportHeight);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final scrollOffsetController = ScrollOffsetController();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: _viewportWidth,
          height: _viewportHeight,
          child: ZoomView(
            controller: ScrollOffsetToScrollController(
              scrollOffsetController: scrollOffsetController,
            ),
            scrollAxis: Axis.vertical,
            maxScale: 5,
            pinchEnabled: pinchEnabled,
            forceHoldOnPointerDown: forceHoldOnPointerDown,
            onScaleChanged: onScaleChanged,
            child: ScrollablePositionedList.builder(
              scrollOffsetController: scrollOffsetController,
              itemCount: 50,
              itemBuilder: (context, index) =>
                  SizedBox(height: _itemHeight, child: Text('Item $index')),
            ),
          ),
        ),
      ),
    ),
  );
  // Let the list mount and attach controllers.
  await tester.pumpAndSettle();
}

/// Drive a two-finger pinch-out gesture (two pointers moving apart).
Future<void> _simulatePinchOut(WidgetTester tester) async {
  final center = const Offset(_viewportWidth / 2, _viewportHeight / 2);
  // Start two fingers near the center, ~60px apart, then pull them apart
  // along the diagonal so the scale delta is significant.
  final start1 = center + const Offset(-30, -30);
  final start2 = center + const Offset(30, 30);
  final g1 = await tester.startGesture(start1);
  final g2 = await tester.startGesture(start2);
  // Pull them apart over several frames to give the scale recognizer time
  // to accept past its slop threshold.
  for (var i = 0; i < 10; i++) {
    await g1.moveBy(const Offset(-10, -10));
    await g2.moveBy(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g1.up();
  await g2.up();
  await tester.pumpAndSettle();
}

void main() {
  group('ZoomView + ScrollablePositionedList pinch wiring', () {
    testWidgets('with forceHold a pinch fires the scale callback', (
      tester,
    ) async {
      double? lastScale;
      await _pumpZoomWrappedList(
        tester,
        forceHoldOnPointerDown: true,
        onScaleChanged: (scale) => lastScale = scale,
      );
      await _simulatePinchOut(tester);
      expect(
        lastScale,
        isNotNull,
        reason:
            'onScaleChanged should fire when forceHoldOnPointerDown is '
            'set — that is the whole point of the flag for SPL',
      );
      expect(lastScale!, greaterThan(1.0));
    });

    testWidgets(
      'a disabled pinch is ignored, and single-finger scrolling works',
      (tester) async {
        double? lastScale;
        await _pumpZoomWrappedList(
          tester,
          forceHoldOnPointerDown: true,
          pinchEnabled: false,
          onScaleChanged: (scale) => lastScale = scale,
        );
        await _simulatePinchOut(tester);
        expect(
          lastScale,
          isNull,
          reason: 'pinch disabled must ignore the gesture',
        );

        // A single-finger drag still scrolls the underlying list.
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpZoomWrappedList(
          tester,
          forceHoldOnPointerDown: true,
          onScaleChanged: (_) {},
        );
        expect(
          tester.getTopLeft(find.text('Item 0')).dy,
          closeTo(0.0, 0.5),
          reason: 'sanity: list starts at the top',
        );
        await tester.drag(
          find.byType(ScrollablePositionedList),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        final item0Finder = find.text('Item 0');
        if (item0Finder.evaluate().isNotEmpty) {
          expect(
            tester.getTopLeft(item0Finder).dy,
            lessThan(-50.0),
            reason: 'ZoomView must not block normal scrolling',
          );
        }
      },
    );
  });
}
