// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/next_update/next_update_predictor.dart';
import 'package:tsumiru/src/features/manga_book/domain/next_update/release_pattern.dart';

void main() {
  final now = DateTime(2026, 6, 23);
  int daysAgoMs(int d) =>
      now.subtract(Duration(days: d)).millisecondsSinceEpoch;

  ChapterRelease up(int d) => (uploadMs: daysAgoMs(d), fetchMs: daysAgoMs(d));

  group('predictNextUpdate interval', () {
    test('huge gaps clamp at 28, fewer than 3 chapters defaults to 7', () {
      final clamped = predictNextUpdate([
        up(1),
        up(60),
        up(120),
        up(180),
      ], now: now);
      expect(clamped.intervalDays, 28);

      final sparse = predictNextUpdate([up(0), up(40)], now: now);
      expect(sparse.intervalDays, 7);
    });
  });

  group('predictNextUpdate days/Soon', () {
    test('overdue rolls forward to the next future cycle (Komikku)', () {
      // weekly, latest 10 days ago. Projects whole cycles forward:
      // cycle = 10 // 7 = 1, nextUpdate = latest + 2*7 = 4 days out.
      final p = predictNextUpdate([up(10), up(17), up(24), up(31)], now: now);
      expect(p.daysUntil(now), 4);
    });
  });

  group('release schedule patterns (Mihon FetchIntervalTest)', () {
    DateTime day(int y, int m, int d) => DateTime(y, m, d);
    ChapterRelease on(DateTime d) {
      final ms = DateTime(d.year, d.month, d.day, 12).millisecondsSinceEpoch;
      return (uploadMs: ms, fetchMs: ms);
    }

    List<ChapterRelease> chaptersOn(List<DateTime> days, {int perDay = 1}) => [
          for (final d in days)
            for (var i = 0; i < perDay; i++) on(d),
        ];
    List<DateTime> every(int step, DateTime from, DateTime to) {
      final out = <DateTime>[];
      for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + step)) {
        out.add(d);
      }
      return out;
    }

    DateTime? nextOn(List<ChapterRelease> chapters, DateTime today) =>
        predictNextUpdate(chapters, now: today).nextUpdate;

    test('follows weekday, weekly, early, late and future-dated schedules', () {
      final mondaysAndThursdays = every(1, day(2019, 12, 2), day(2020, 1, 20))
          .where((d) => d.weekday == DateTime.monday || d.weekday == DateTime.thursday)
          .toList();
      final weekdayChapters = chaptersOn(mondaysAndThursdays);
      expect(nextOn(weekdayChapters, day(2020, 1, 21)), day(2020, 1, 23));
      expect(
        predictNextUpdate(weekdayChapters, now: day(2020, 1, 21)).intervalDays,
        4,
      );

      final weekly = chaptersOn(every(7, day(2019, 12, 4), day(2019, 12, 25)));
      expect(nextOn(weekly, day(2020, 1, 1)), day(2020, 1, 1));

      final early = chaptersOn(
        every(7, day(2019, 10, 2), day(2019, 12, 25)) + [day(2019, 12, 30)],
      );
      expect(nextOn(early, day(2019, 12, 30)), day(2020, 1, 8));

      final late = chaptersOn(
        every(7, day(2019, 12, 4), day(2019, 12, 25)) + [day(2020, 1, 3)],
      );
      expect(nextOn(late, day(2020, 1, 3)), day(2020, 1, 8));

      final future = chaptersOn(
        every(7, day(2019, 12, 4), day(2019, 12, 25)) + [day(2020, 6, 1)],
      );
      expect(nextOn(future, day(2020, 1, 1)), day(2020, 1, 1));

      var from = day(2019, 10, 18);
      final overdueDays = <DateTime>[from];
      for (final gap in [6, 5, 8, 6, 5, 6, 8, 6, 5]) {
        from = DateTime(from.year, from.month, from.day + gap);
        overdueDays.add(from);
      }
      final overdue = chaptersOn(overdueDays);
      expect(nextOn(overdue, day(2019, 12, 20)), day(2019, 12, 20));
      expect(
        predictNextUpdate(overdue, now: day(2019, 12, 20)).intervalDays,
        6,
      );

      // Pacific/Apia skipped 2011-12-30; calendar maths must still land on it.
      final apiaChapters = chaptersOn([
        day(2011, 12, 27),
        day(2011, 12, 28),
        day(2011, 12, 29),
      ]);
      final apiaToday = DateTime.utc(2011, 12, 29);
      expect(
        ReleaseSchedule.estimate(apiaChapters, apiaToday).nextCheck(apiaToday),
        DateTime.utc(2011, 12, 30),
      );
      expect(
        const Weekdays({DateTime.monday, DateTime.thursday})
            .previousBefore(DateTime.utc(2011, 12, 31)),
        DateTime.utc(2011, 12, 29),
      );
    });

    test('follows monthly schedules', () {
      List<DateTime> dates(List<String> iso) => [
            for (final s in iso)
              day(
                int.parse(s.substring(0, 4)),
                int.parse(s.substring(5, 7)),
                int.parse(s.substring(8, 10)),
              ),
          ];

      final dayOfMonth = chaptersOn(
        dates(['2019-09-15', '2019-10-15', '2019-11-14', '2019-12-15', '2020-01-16']),
        perDay: 2,
      );
      expect(nextOn(dayOfMonth, day(2020, 1, 20)), day(2020, 2, 15));

      final lastDay = chaptersOn(
        dates(['2019-09-30', '2019-10-31', '2019-11-30', '2019-12-31', '2020-01-31']),
        perDay: 2,
      );
      expect(nextOn(lastDay, day(2020, 2, 5)), day(2020, 2, 29));
      expect(nextOn(lastDay, day(2020, 1, 31)), day(2020, 2, 28));

      final twiceMonthly = chaptersOn(
        dates([
          '2019-10-01',
          '2019-10-15',
          '2019-11-01',
          '2019-11-16',
          '2019-12-01',
          '2019-12-15',
          '2020-01-01',
          '2020-01-15',
        ]),
        perDay: 2,
      );
      expect(nextOn(twiceMonthly, day(2020, 1, 20)), day(2020, 2, 1));
      expect(
        predictNextUpdate(twiceMonthly, now: day(2020, 1, 20)).intervalDays,
        15,
      );

      final firstSaturdays = chaptersOn(
        dates(['2019-09-07', '2019-10-05', '2019-11-02', '2019-12-07', '2020-01-04']),
        perDay: 2,
      );
      expect(nextOn(firstSaturdays, day(2020, 1, 10)), day(2020, 2, 1));

      final lastFridays = chaptersOn(
        dates(['2019-09-27', '2019-10-25', '2019-11-29', '2019-12-27', '2020-01-31']),
        perDay: 2,
      );
      expect(nextOn(lastFridays, day(2020, 2, 3)), day(2020, 2, 28));
    });

    test('follows batches and handles breaks with back-off', () {
      final batches = [
        for (final start in every(21, day(2019, 9, 2), day(2019, 12, 16)))
          for (var i = 0; i < 3; i++)
            DateTime(start.year, start.month, start.day + i),
      ];
      final batchChapters = chaptersOn(batches);
      expect(nextOn(batchChapters, day(2019, 12, 19)), day(2020, 1, 6));
      expect(
        predictNextUpdate(batchChapters, now: day(2019, 12, 19)).intervalDays,
        21,
      );

      final seasons = chaptersOn(
        every(7, day(2019, 1, 2), day(2019, 3, 27)) +
            every(7, day(2019, 7, 3), day(2019, 9, 25)),
      );
      expect(nextOn(seasons, day(2019, 12, 20)), day(2019, 12, 25));
      expect(nextOn(seasons, day(2019, 12, 26)), day(2020, 1, 1));

      final hiatus = chaptersOn(every(7, day(2019, 9, 11), day(2019, 10, 2)));
      expect(nextOn(hiatus, day(2020, 1, 1)), day(2020, 1, 22));
    });
  });
}
