// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// MeasureSize is what lets the webtoon reader record a page image's true
// rendered height the first time it lays out, so a page re-entering the
// viewport on a long backward scroll can reserve that height instead of
// collapsing to a small placeholder and snapping the scroll. These tests pin
// the two behaviours the fix depends on: it reports the child's height, and it
// reports again when the child grows (image decode).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/measure_size.dart';

void main() {
  testWidgets('reports the child height once laid out', (tester) async {
    final sizes = <Size>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          children: [
            MeasureSize(
              onChange: sizes.add,
              child: const SizedBox(height: 1234, width: 400),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sizes.last.height, 1234);
  });

  testWidgets('reports the new height when the child grows (decode)',
      (tester) async {
    final sizes = <Size>[];
    final height = ValueNotifier<double>(420); // placeholder
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          children: [
            MeasureSize(
              onChange: sizes.add,
              child: ValueListenableBuilder<double>(
                valueListenable: height,
                builder: (_, h, __) => SizedBox(height: h, width: 400),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sizes.last.height, 420);

    height.value = 5400; // image decodes to ~9 viewports
    await tester.pumpAndSettle();
    expect(sizes.last.height, 5400);
  });
}
