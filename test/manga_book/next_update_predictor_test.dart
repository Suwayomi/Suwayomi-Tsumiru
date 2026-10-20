// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/next_update/next_update_predictor.dart';

void main() {
  final now = DateTime(2026, 6, 23);
  int daysAgoMs(int d) =>
      now.subtract(Duration(days: d)).millisecondsSinceEpoch;

  ChapterRelease up(int d) => (uploadMs: daysAgoMs(d), fetchMs: daysAgoMs(d));

  group('predictNextUpdate interval', () {
    test('huge gaps clamp at 28', () {
      final p = predictNextUpdate([up(1), up(60), up(120), up(180)], now: now);
      expect(p.intervalDays, 28);
    });

    test('fewer than 3 dated chapters → default 7', () {
      final p = predictNextUpdate([up(0), up(40)], now: now);
      expect(p.intervalDays, 7);
    });
  });

  group('predictNextUpdate days/Soon', () {
    test('overdue rolls forward to the next future cycle (Komikku)', () {
      // weekly, latest 10 days ago. Projects whole cycles forward:
      // cycle = 10 // 7 = 1, nextUpdate = latest + 2*7 = 4 days out.
      final p = predictNextUpdate([up(10), up(17), up(24), up(31)], now: now);
      expect(p.daysUntil(now), 4);
    });

    test('no chapters → null prediction', () {
      final p = predictNextUpdate(const [], now: now);
      expect(p.nextUpdate, isNull);
      expect(p.daysUntil(now), isNull);
    });
  });
}
