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
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
  }

  group('convertToDaysAgo', () {
    testWidgets('today reads as Today and late yesterday as Yesterday', (
      tester,
    ) async {
      await pump(tester);
      final now = DateTime.now();
      final earlyToday = DateTime(now.year, now.month, now.day, 0, 0, 1);
      expect(now.convertToDaysAgo(context), 'Today');
      expect(earlyToday.convertToDaysAgo(context), 'Today');

      // Calendar-day counting, not a rolling 24h count: from 23:59:59
      // yesterday, elapsed time stays under 24h for almost all of today.
      final lateYesterday = DateTime(
        now.year,
        now.month,
        now.day - 1,
        23,
        59,
        59,
      );
      expect(lateYesterday.convertToDaysAgo(context), 'Yesterday');
    });

    testWidgets('late two days ago reads as "2 days ago" in both helpers', (
      tester,
    ) async {
      await pump(tester);
      final now = DateTime.now();
      final lateTwoDaysAgo = DateTime(
        now.year,
        now.month,
        now.day - 2,
        23,
        59,
        59,
      );
      expect(lateTwoDaysAgo.convertToDaysAgo(context), '2 days ago');
      expect(lateTwoDaysAgo.convertToTimeAgo(context), '2 days ago');
    });
  });
}
