// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// The vertical side seekbar's two buttons used to jump to the first/last page
// of the chapter, while the paged reader's identical glyphs changed chapter.
// Same icon, two meanings. Both now change chapter, matching Komikku's
// ChapterNavigatorVert.

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
      await pump(tester, onPreviousChapter: () => previousCalls++,
          onNextChapter: () {});

      await tester.tap(find.byType(BrandFilledCircleButton).first);
      await tester.pumpAndSettle();

      expect(previousCalls, 1);
    });

    testWidgets('bottom button opens the next chapter', (tester) async {
      var nextCalls = 0;
      await pump(tester, onPreviousChapter: () {},
          onNextChapter: () => nextCalls++);

      await tester.tap(find.byType(BrandFilledCircleButton).last);
      await tester.pumpAndSettle();

      expect(nextCalls, 1);
    });

    testWidgets('buttons no longer seek within the chapter', (tester) async {
      final seeks = <int>[];
      await pump(
        tester,
        onPreviousChapter: () {},
        onNextChapter: () {},
        onChanged: seeks.add,
      );

      await tester.tap(find.byType(BrandFilledCircleButton).first);
      await tester.tap(find.byType(BrandFilledCircleButton).last);
      await tester.pumpAndSettle();

      expect(seeks, isEmpty,
          reason: 'jumping to page 0 / last page was the old behavior');
    });

    testWidgets('no adjacent chapter disables the button', (tester) async {
      await pump(tester, onPreviousChapter: null, onNextChapter: null);

      final buttons = tester
          .widgetList<BrandFilledCircleButton>(
              find.byType(BrandFilledCircleButton))
          .toList();

      expect(buttons, hasLength(2));
      expect(buttons.first.onPressed, isNull);
      expect(buttons.last.onPressed, isNull);
    });
  });
}
