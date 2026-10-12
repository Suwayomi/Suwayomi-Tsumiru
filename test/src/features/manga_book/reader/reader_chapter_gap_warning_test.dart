// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_chapter_gap_warning.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/infinity_continuous_feedback.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('gap forces a warning even with transitions disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const InfinityContinuousChapterSeparator(
          chapterName: 'Chapter 1',
          isChapterStart: false,
          alwaysShow: false,
          gapCount: 3,
        ),
      ),
    );
    expect(find.byType(ReaderChapterGapWarning), findsOneWidget);
    expect(find.textContaining('Skipping 3 chapters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final continueReading in [false, true]) {
    testWidgets('confirmation returns $continueReading', (tester) async {
      bool? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await confirmReaderChapterGap(context, 1);
              },
              child: const Text('Navigate'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Navigate'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Skipping 1 chapter.'), findsOneWidget);
      await tester.tap(find.text(continueReading ? 'Continue' : 'Cancel'));
      await tester.pumpAndSettle();
      expect(result, continueReading);
    });
  }
}
