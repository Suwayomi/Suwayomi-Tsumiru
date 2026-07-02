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
    test('weekly cadence → interval 7', () {
      final p = predictNextUpdate(
        [up(2), up(9), up(16), up(23)],
        now: now,
      );
      expect(p.intervalDays, 7);
      // latest 2 days ago + 7 → 5 days out.
      expect(p.daysUntil(now), 5);
    });

    test('biweekly cadence → interval 14', () {
      final p = predictNextUpdate(
        [up(1), up(15), up(29), up(43)],
        now: now,
      );
      expect(p.intervalDays, 14);
    });

    test('huge gaps clamp at 28', () {
      final p = predictNextUpdate(
        [up(1), up(60), up(120), up(180)],
        now: now,
      );
      expect(p.intervalDays, 28);
    });

    test('fewer than 3 dated chapters → default 7', () {
      final p = predictNextUpdate([up(0), up(40)], now: now);
      expect(p.intervalDays, 7);
    });

    test('falls back to fetch dates when upload dates are absent', () {
      final c = <ChapterRelease>[
        for (final d in [2, 9, 16, 23]) (uploadMs: 0, fetchMs: daysAgoMs(d)),
      ];
      final p = predictNextUpdate(c, now: now);
      expect(p.intervalDays, 7);
    });
  });

  group('predictNextUpdate days/Soon', () {
    test('not yet due → positive days', () {
      // weekly, latest 3 days ago → due in 4.
      final p = predictNextUpdate([up(3), up(10), up(17), up(24)], now: now);
      expect(p.daysUntil(now), 4);
    });

    test('overdue rolls forward to the next future cycle (Komikku)', () {
      // weekly, latest 10 days ago. Projects whole cycles forward:
      // cycle = 10 // 7 = 1, nextUpdate = latest + 2*7 = 4 days out.
      final p = predictNextUpdate([up(10), up(17), up(24), up(31)], now: now);
      expect(p.daysUntil(now), 4);
    });

    test('long-dormant series still projects a future date, not Soon', () {
      // ~58 days since last release, weekly cadence (the "Surviving the Game"
      // case). cycle = 58 // 7 = 8, nextUpdate = latest + 9*7 = 63 days from
      // latest = 5 days out. Must NOT floor to 0/"Soon".
      final p = predictNextUpdate(
        [up(58), up(65), up(72), up(79)],
        now: now,
      );
      expect(p.intervalDays, 7);
      expect(p.daysUntil(now), 5);
    });

    test('no chapters → null prediction', () {
      final p = predictNextUpdate(const [], now: now);
      expect(p.nextUpdate, isNull);
      expect(p.daysUntil(now), isNull);
    });

    test('duplicate same-day releases do not skew the gap', () {
      // Three chapters on the same day shouldn't read as a 0-day cadence.
      final c = <ChapterRelease>[
        up(2), up(2), up(2), up(9), up(16), up(23),
      ];
      final p = predictNextUpdate(c, now: now);
      expect(p.intervalDays, 7);
    });
  });
}
