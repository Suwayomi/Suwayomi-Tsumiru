// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/utils/wheel_scroll.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/mouse_wheel_speed.dart';

double? _target({
  double pixels = 500,
  double rawDelta = 53,
  bool reverse = false,
  double speed = 1.7,
  double minExtent = 0,
  double maxExtent = 10000,
  double? pendingTarget,
}) =>
    wheelScrollTarget(
      pixels: pixels,
      rawDelta: rawDelta,
      reverse: reverse,
      speed: speed,
      minExtent: minExtent,
      maxExtent: maxExtent,
      pendingTarget: pendingTarget,
    );

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
  // Tests pump two trees in a row; without clearing, the second inherits the
  // first one's scroll offset because the subtree shape is unchanged.
  await tester.pumpWidget(const SizedBox.shrink());
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
  test('notches during a glide stack onto the pending target', () {
    final first = _target(pixels: 500, speed: 1.7);
    final second = _target(pixels: 520, pendingTarget: first, speed: 1.7);
    expect(second, closeTo(500 + 53 * 1.7 * 2, 0.001));
    expect(
      _target(pixels: 9000, pendingTarget: 9950, speed: 4, maxExtent: 10000),
      10000,
    );
  });

  testWidgets('a burst of small wheel events moves smoothly, without jumps', (
    tester,
  ) async {
    final controller = await _pump(tester, speed: 1.7);
    final position = controller.position;
    final center = tester.getCenter(find.byType(ListView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);

    final samples = <double>[position.pixels];
    for (var i = 0; i < 10; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 8)));
      await tester.pump(const Duration(milliseconds: 16));
      samples.add(position.pixels);
    }
    await tester.pumpAndSettle();
    samples.add(position.pixels);

    for (var i = 1; i < samples.length; i++) {
      expect(
        samples[i],
        greaterThan(samples[i - 1]),
        reason: 'frame $i stalled or went backwards: $samples',
      );
    }
    final total = samples.last - samples.first;
    expect(total, closeTo(10 * 8 * 1.7, 0.5));
    final largestStep = [
      for (var i = 1; i < samples.length; i++) samples[i] - samples[i - 1],
    ].reduce((a, b) => a > b ? a : b);
    expect(
      largestStep,
      lessThan(total * 0.4),
      reason: 'one frame covered too much of the move: $samples',
    );
  });
}
