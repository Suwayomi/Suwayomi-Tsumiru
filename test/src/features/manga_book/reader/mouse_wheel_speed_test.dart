// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/mouse_wheel_speed.dart';

/// Drives a real Scrollable so the platform's own wheel handling and ours are
/// both in play — the composition is the thing that can break, not the maths.
Future<ScrollController> _pump(
  WidgetTester tester, {
  required double speed,
  bool reverse = false,
  Axis axis = Axis.vertical,
}) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: MouseWheelSpeed(
            speed: speed,
            axis: axis,
            reverse: reverse,
            positionOf: () =>
                controller.hasClients ? controller.position : null,
            child: ListView.builder(
              controller: controller,
              scrollDirection: axis,
              reverse: reverse,
              itemCount: 200,
              itemBuilder: (_, i) =>
                  SizedBox(width: 400, height: 200, child: Text('$i')),
            ),
          ),
        ),
      ),
    ),
  );
  return controller;
}

Future<void> _wheel(WidgetTester tester, Offset delta) async {
  final center = tester.getCenter(find.byType(ListView));
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  pointer.hover(center);
  await tester.sendEventToBinding(pointer.scroll(delta));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one notch travels the multiple of the platform distance', (
    tester,
  ) async {
    final plain = await _pump(tester, speed: 1);
    await _wheel(tester, const Offset(0, 53));
    final base = plain.position.pixels;
    expect(base, greaterThan(0), reason: 'the platform did not scroll at all');

    final scaled = await _pump(tester, speed: 1.7);
    await _wheel(tester, const Offset(0, 53));
    expect(scaled.position.pixels, closeTo(base * 1.7, 0.5));
  });

  testWidgets('a slower speed travels less than the platform would', (
    tester,
  ) async {
    final plain = await _pump(tester, speed: 1);
    await _wheel(tester, const Offset(0, 53));
    final base = plain.position.pixels;

    final slow = await _pump(tester, speed: 0.5);
    await _wheel(tester, const Offset(0, 53));
    expect(slow.position.pixels, closeTo(base * 0.5, 0.5));
  });

  testWidgets('a reversed list travels the same distance, not less', (
    tester,
  ) async {
    // A reversed list rests at 0, where a downward notch has nowhere to go.
    // Move into the middle first so there is travel in both directions.
    final plain = await _pump(tester, speed: 1, reverse: true);
    plain.jumpTo(1000);
    await tester.pumpAndSettle();
    await _wheel(tester, const Offset(0, 53));
    final base = 1000 - plain.position.pixels;
    expect(base, isNot(0), reason: 'the platform did not scroll at all');

    final scaled = await _pump(tester, speed: 1.7, reverse: true);
    scaled.jumpTo(1000);
    await tester.pumpAndSettle();
    await _wheel(tester, const Offset(0, 53));
    expect(1000 - scaled.position.pixels, closeTo(base * 1.7, 0.5));
  });

  testWidgets('it stops at the top instead of overshooting past it', (
    tester,
  ) async {
    final controller = await _pump(tester, speed: 4);
    await _wheel(tester, const Offset(0, -53));
    expect(controller.position.pixels, 0);
  });

  testWidgets('a trackpad is left to the platform', (tester) async {
    final controller = await _pump(tester, speed: 4);
    final center = tester.getCenter(find.byType(ListView));
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    pointer.hover(center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 53)));
    await tester.pumpAndSettle();
    expect(controller.position.pixels, closeTo(53, 0.5));
  });
}
