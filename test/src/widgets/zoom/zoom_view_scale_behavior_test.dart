// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Verifies zoom-in/zoom-out behaves correctly for BOTH reading axes:
//   - Axis.vertical   (webtoon / continuous vertical)
//   - Axis.horizontal (continuous horizontal LTR/RTL)
//
// ZoomView was originally written with only a vertical list in mind, so
// several of its internal formulas hard-coded which controller is the "main"
// (real scroll position) axis vs. the "cross" (synthetic pan) axis. That
// hard-coding was only ever correct for Axis.vertical — every check here
// runs the same scenario on both axes so a regression that only shows up in
// horizontal mode (e.g. #zoom-view-axis-centering, #zoom-view-gesture-arena)
// fails loudly instead of hiding behind "webtoon works, nobody re-tested
// horizontal".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/widgets/zoom/zoom_view.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

const double _viewportWidth = 400.0;
const double _viewportHeight = 800.0;
const _pageKey = ValueKey('page');

/// The real on-screen magnification of [finder]'s render object, read off its
/// paint transform. Unlike [WidgetTester.getSize] (which returns the
/// pre-FittedBox LOGICAL layout size and never changes), this reflects the
/// actual visual zoom applied by ZoomView's FittedBox.
double _paintScaleOf(Finder finder) {
  final transform = finder.evaluate().first.renderObject!.getTransformTo(null);
  final unit = transform.transform3(Vector3(1, 0, 0)) -
      transform.transform3(Vector3(0, 0, 0));
  return unit.length;
}

class _Harness {
  _Harness(this.tester, this.scrollAxis, {this.reverse = false})
      : mainController = ScrollController(),
        zoomController = ZoomViewController();

  final WidgetTester tester;
  final Axis scrollAxis;
  final bool reverse;
  final ScrollController mainController;
  final ZoomViewController zoomController;

  /// A single page-sized item so the paint-scale probe has something to
  /// measure, inside a list long enough to give the main axis real scroll
  /// range (mirrors the reader: many pages laid end-to-end along scrollAxis).
  Future<void> pump({double minScale = 1.0, double maxScale = 4.0}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(_viewportWidth, _viewportHeight);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

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
              minScale: minScale,
              maxScale: maxScale,
              child: ListView(
                controller: mainController,
                scrollDirection: scrollAxis,
                reverse: reverse,
                children: [
                  for (var i = 0; i < 5; i++)
                    SizedBox(
                      width: _viewportWidth,
                      height: _viewportHeight,
                      // Index 0 so the paint-scale probe is visible in a lazy
                      // ListView even before any main-axis scrolling happens.
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
  }

  double get mainAxisPixels => mainController.position.pixels;
  double get paintScale => _paintScaleOf(find.byKey(_pageKey));
}

void main() {
  for (final axis in [Axis.vertical, Axis.horizontal]) {
    for (final reverse in [false, true]) {
      group('ZoomView scale behaviour — scrollAxis: $axis, reverse: $reverse',
          () {
        testWidgets('zooming in magnifies the content on screen',
            (tester) async {
          final h = _Harness(tester, axis, reverse: reverse);
          await h.pump();
          expect(h.paintScale, closeTo(1.0, 0.001),
              reason: 'unzoomed content must render at 1:1');

          h.zoomController.setScale(2.0);
          await tester.pumpAndSettle();

          expect(h.paintScale, closeTo(2.0, 0.01),
              reason: 'setScale(2.0) must actually double the on-screen '
                  'size, not just the reported logical layout size');
        });

        testWidgets(
            'zooming back out to 1x restores the original on-screen size',
            (tester) async {
          final h = _Harness(tester, axis, reverse: reverse);
          await h.pump();

          h.zoomController.setScale(3.0);
          await tester.pumpAndSettle();
          expect(h.paintScale, closeTo(3.0, 0.01));

          h.zoomController.setScale(1.0);
          await tester.pumpAndSettle();
          expect(h.paintScale, closeTo(1.0, 0.01),
              reason: 'zooming back out must return to the original size');
        });

        testWidgets(
            'zoom in/out round trip does not shift the main-axis scroll '
            'position (regression: axis-centering bug jumped the page)',
            (tester) async {
          final h = _Harness(tester, axis, reverse: reverse);
          await h.pump();

          // Scroll to a non-trivial, non-edge position first — mirrors
          // having read partway through a chapter before touching zoom.
          h.mainController.jumpTo(600);
          await tester.pumpAndSettle();
          final beforeZoom = h.mainAxisPixels;

          // Double-tap-to-zoom-in, from the reader's own on-screen center.
          h.zoomController.setScaleWithAnimation(
            3.0,
            focalPoint: const Offset(_viewportWidth / 2, _viewportHeight / 2),
          );
          await tester.pumpAndSettle();

          // ...then straight back out to 1x, like a second double-tap.
          h.zoomController.setScaleWithAnimation(
            1.0,
            focalPoint: const Offset(_viewportWidth / 2, _viewportHeight / 2),
          );
          await tester.pumpAndSettle();

          expect(h.mainAxisPixels, closeTo(beforeZoom, 1.0),
              reason: 'returning to 1x must land back where the user '
                  'actually was — a center-focal-point zoom in and back out '
                  'should be a no-op on the main scroll axis, not silently '
                  'jump the page');
        });

        testWidgets(
            'zoom-out below 1x and back round trip does not shift the '
            'main-axis scroll position (regression: axis-centering bug)',
            (tester) async {
          final h = _Harness(tester, axis, reverse: reverse);
          await h.pump(minScale: 0.5); // long-strip "allow zoom out" setting

          h.mainController.jumpTo(600);
          await tester.pumpAndSettle();
          final beforeZoom = h.mainAxisPixels;

          h.zoomController.setScaleWithAnimation(
            0.5,
            focalPoint: const Offset(_viewportWidth / 2, _viewportHeight / 2),
          );
          await tester.pumpAndSettle();

          h.zoomController.setScaleWithAnimation(
            1.0,
            focalPoint: const Offset(_viewportWidth / 2, _viewportHeight / 2),
          );
          await tester.pumpAndSettle();

          expect(h.mainAxisPixels, closeTo(beforeZoom, 1.0),
              reason: 'zooming below 1x and back must not drift the '
                  'main-axis position — this is exactly the '
                  'internal-scale > 1.0 branch that used to hard-code the '
                  'horizontal controller as the "centered" one regardless '
                  'of scrollAxis');
        });
      });
    }
  }
}
