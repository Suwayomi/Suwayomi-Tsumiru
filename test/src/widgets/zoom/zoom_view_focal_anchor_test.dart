// Diagnostic: verifies the zoom focal point stays anchored on screen through
// a SINGLE zoom step, on both scrollAxis values, EACH with reverse false and
// true (an RTL manga's continuous-horizontal strip is scrollAxis: horizontal,
// reverse: true — the exact combination that used to mirror pinch/double-tap
// zoom on the main axis while the cross axis stayed correct), for BOTH axes
// at once (an off-center local point has a nonzero component on each), and
// for both ways a zoom step can happen: `setScaleWithAnimation`
// (double-tap-to-zoom) and a live two-finger pinch (`DragMode.pinchScale` in
// ZoomView's own `onScaleUpdate`) — two separate code paths with their own
// scroll-target math. Round-trip tests (zoom in then back to 1x) can pass
// even with a per-step anchor bug if the same wrong formula is applied
// symmetrically forward and backward — this test checks the intermediate
// zoomed state directly instead.
//
// Method: pick a fixed local point inside a list item that never changes its
// own logical (pre-FittedBox) size when `_scale` changes — only the
// FittedBox's transform around the whole list does. So the same local
// offset on that item's RenderBox always denotes the same content point;
// mapping it to global (screen) coordinates before and after a zoom
// centered on that exact point isolates the anchor math from every layout
// detail of the surrounding scroll views.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/widgets/zoom/zoom_view.dart';

const double _viewportWidth = 400.0;
const double _viewportHeight = 800.0;
const _pageKey = ValueKey('page');

/// Global (screen) position of [localPoint] inside the page marked by
/// [_pageKey], accounting for the FittedBox scale ZoomView applies.
Offset _globalPositionOf(Offset localPoint) {
  final renderBox =
      find.byKey(_pageKey).evaluate().first.renderObject! as RenderBox;
  return renderBox.localToGlobal(localPoint);
}

Future<ZoomViewController> _pumpHarness(
  WidgetTester tester, {
  required Axis scrollAxis,
  bool reverse = false,
  bool pinchEnabled = true,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(_viewportWidth, _viewportHeight);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final mainController = ScrollController();
  final zoomController = ZoomViewController();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: _viewportWidth,
          height: _viewportHeight,
          child: ZoomView(
            controller: mainController,
            zoomViewController: zoomController,
            scrollAxis: scrollAxis,
            reverse: reverse,
            minScale: 1.0,
            maxScale: 4.0,
            pinchEnabled: pinchEnabled,
            child: ListView(
              controller: mainController,
              scrollDirection: scrollAxis,
              reverse: reverse,
              children: [
                for (var i = 0; i < 5; i++)
                  SizedBox(
                    width: _viewportWidth,
                    height: _viewportHeight,
                    child: i == 0
                        ? const ColoredBox(
                            key: _pageKey,
                            color: Colors.red,
                          )
                        : ColoredBox(
                            color: i.isEven ? Colors.blue : Colors.green,
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return zoomController;
}

// Off-center on purpose (not the viewport/page center, and not (0,0)) so a
// bug specific to one axis or one sign shows up clearly.
const _localFocal = Offset(120, 250);

void main() {
  for (final axis in [Axis.vertical, Axis.horizontal]) {
    for (final reverse in [false, true]) {
      final label = 'scrollAxis: $axis, reverse: $reverse';

      testWidgets(
          'setScaleWithAnimation keeps an off-center focal point anchored on '
          'screen — $label', (tester) async {
        final zoomController =
            await _pumpHarness(tester, scrollAxis: axis, reverse: reverse);

        final focalBefore = _globalPositionOf(_localFocal);
        zoomController.setScaleWithAnimation(2.0, focalPoint: focalBefore);
        await tester.pumpAndSettle();
        final focalAfter = _globalPositionOf(_localFocal);

        expect(
          (focalAfter - focalBefore).distance,
          lessThan(5.0),
          reason: 'zooming in centered on a point must leave that point '
              'where it was on screen — before: $focalBefore, after: '
              '$focalAfter (dx drift: '
              '${(focalAfter.dx - focalBefore.dx).abs()}, dy drift: '
              '${(focalAfter.dy - focalBefore.dy).abs()})',
        );
      });

      testWidgets(
          'a live two-finger pinch keeps its focal point anchored on '
          'screen — $label', (tester) async {
        await _pumpHarness(tester, scrollAxis: axis, reverse: reverse);

        final focalBefore = _globalPositionOf(_localFocal);

        final g1 =
            await tester.startGesture(focalBefore + const Offset(-20, 0));
        final g2 =
            await tester.startGesture(focalBefore + const Offset(20, 0));
        for (var i = 0; i < 20; i++) {
          await g1.moveBy(const Offset(-2, 0));
          await g2.moveBy(const Offset(2, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g1.up();
        await g2.up();
        await tester.pumpAndSettle();

        final focalAfter = _globalPositionOf(_localFocal);

        expect(
          (focalAfter - focalBefore).distance,
          lessThan(15.0),
          reason: 'the pinched point must stay under the fingers as the '
              'content scales up around it — before: $focalBefore, '
              'after: $focalAfter (dx drift: '
              '${(focalAfter.dx - focalBefore.dx).abs()}, dy drift: '
              '${(focalAfter.dy - focalBefore.dy).abs()})',
        );
      });
    }
  }
}
