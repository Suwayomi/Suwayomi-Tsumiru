// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';

void main() {
  late BuildContext context;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (ctx) {
          context = ctx;
          return const SizedBox();
        },
      ),
    ));
    await tester.pump();
  }

  group('convertToDaysAgo', () {
    testWidgets('today reads as Today, early or late in the day',
        (tester) async {
      await pump(tester);
      final now = DateTime.now();
      final earlyToday = DateTime(now.year, now.month, now.day, 0, 0, 1);

      expect(now.convertToDaysAgo(context), 'Today');
      expect(earlyToday.convertToDaysAgo(context), 'Today');
    });

    testWidgets(
        'a chapter from late yesterday reads as Yesterday, not Today',
        (tester) async {
      await pump(tester);
      final now = DateTime.now();
      // Regression: DateTime.now().difference(this).inDays is a rolling
      // 24h count, not a calendar-day count. From 23:59:59 yesterday, real
      // elapsed time stays under 24h for virtually the whole of today, so
      // the old code reported 0 days — "Today" — right up until the last
      // second before the next midnight.
      final lateYesterday =
          DateTime(now.year, now.month, now.day - 1, 23, 59, 59);

      expect(lateYesterday.convertToDaysAgo(context), 'Yesterday');
    });

    testWidgets(
        'a chapter from late two days ago reads as "2 days ago", not '
        'Yesterday', (tester) async {
      await pump(tester);
      final now = DateTime.now();
      // Same rolling-duration trap one slot further back: real elapsed time
      // from 23:59:59 two calendar days ago is always under 48h (however
      // late in today it currently is), so the old code floored it to 1 day
      // — "Yesterday" — instead of the true calendar gap of 2.
      final lateTwoDaysAgo =
          DateTime(now.year, now.month, now.day - 2, 23, 59, 59);

      expect(lateTwoDaysAgo.convertToDaysAgo(context), '2 days ago');
    });
  });

  group('convertToTimeAgo', () {
    testWidgets(
        'a chapter from late two days ago reads as "2 days ago", not '
        'Yesterday', (tester) async {
      await pump(tester);
      final now = DateTime.now();
      // Real elapsed time here is always over 24h (skipping the hours-ago
      // branch) and under 48h, so this exercises the same day-counting tail
      // as convertToDaysAgo above.
      final lateTwoDaysAgo =
          DateTime(now.year, now.month, now.day - 2, 23, 59, 59);

      expect(lateTwoDaysAgo.convertToTimeAgo(context), '2 days ago');
    });
  });
}
