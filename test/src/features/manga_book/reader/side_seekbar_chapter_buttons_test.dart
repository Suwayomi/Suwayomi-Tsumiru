// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Regression guard for #348: these buttons used to seek within the chapter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_side_seekbar.dart';
import 'package:tsumiru/src/utils/theme/brand.dart';

void main() {
  group('Side seekbar chapter buttons', () {
    Future<void> pump(
      WidgetTester tester, {
      VoidCallback? onPreviousChapter,
      VoidCallback? onNextChapter,
      ValueChanged<int>? onChanged,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              width: 56,
              child: ReaderSideSeekBar(
                currentIndex: 4,
                pageCount: 10,
                onChanged: onChanged ?? (_) {},
                onPreviousChapter: onPreviousChapter,
                onNextChapter: onNextChapter,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('top button opens the previous chapter', (tester) async {
      var previousCalls = 0;
      await pump(
        tester,
        onPreviousChapter: () => previousCalls++,
        onNextChapter: () {},
      );

      await tester.tap(find.byType(BrandFilledCircleButton).first);
      await tester.pumpAndSettle();

      expect(previousCalls, 1);
    });
  });
}
