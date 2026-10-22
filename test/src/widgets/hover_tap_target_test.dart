// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/widgets/hover_tap_target.dart';

void main() {
  testWidgets('uses click cursor, reports mouse hover, ignores touch', (
    tester,
  ) async {
    var hovered = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HoverTapTarget(
            builder: (context, value) {
              hovered = value;
              return const SizedBox(width: 100, height: 40);
            },
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<MouseRegion>(
            find.descendant(
              of: find.byType(HoverTapTarget),
              matching: find.byType(MouseRegion),
            ),
          )
          .cursor,
      SystemMouseCursors.click,
    );

    final center = tester.getCenter(find.byType(HoverTapTarget));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(center);
    await tester.pump();
    expect(hovered, isTrue);

    await mouse.moveTo(center + const Offset(300, 300));
    await tester.pump();
    expect(hovered, isFalse);

    await tester.tap(find.byType(HoverTapTarget));
    await tester.pump();
    expect(hovered, isFalse);
  });
}
