import 'dart:math';

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime day, int n) =>
    DateTime(day.year, day.month, day.day + n);

int daysBetween(DateTime from, DateTime to) => DateTime.utc(
      to.year,
      to.month,
      to.day,
    ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

int mod(int a, int n) => ((a % n) + n) % n;

int medianOf(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[(sorted.length - 1) ~/ 2];
}

int ceilDiv(int a, int b) => -_floorDiv(-a, b);

int _floorDiv(int a, int b) =>
    a >= 0 ? a ~/ b : -((-a + b - 1) ~/ b);

const int _minReleases = 4;
const int _maxWeekdays = 3;
const double _coverage = 0.8;
const int _dayOfMonthTolerance = 3;
const int _monthlyGapMin = 26;
const int _monthlyGapMax = 35;
const int _twiceMonthlyGapMin = 12;
const int _twiceMonthlyGapMax = 18;
const int _batchHistory = 40;
const int _batchGap = 2;
const int _recentBatchRuns = 6;
const int _minBatches = 3;

/// The days an entry is expected to release on.
sealed class ReleasePattern {
  const ReleasePattern();

  /// The first expected release day after [date].
  DateTime nextAfter(DateTime date);

  /// The last expected release day before [date].
  DateTime previousBefore(DateTime date);

  /// The expected release day closest to [date].
  DateTime nearest(DateTime date) {
    final before = previousBefore(addDays(date, 1));
    final after = nextAfter(addDays(date, -1));
    return daysBetween(before, date) <= daysBetween(date, after)
        ? before
        : after;
  }

  static ReleasePattern? detect({
    required List<DateTime> days,
    required List<DateTime> history,
    required int medianGap,
  }) {
    if (days.length < _minReleases) return null;
    final batches = _batches(history);
    if (batches != null) return batches;
    if (medianGap >= _monthlyGapMin && medianGap <= _monthlyGapMax) {
      return _monthly(days);
    }
    if (medianGap >= _twiceMonthlyGapMin &&
        medianGap <= _twiceMonthlyGapMax) {
      return _twiceMonthly(days);
    }
    return _weekdays(days, medianGap);
  }
}

/// Releases every [days] days, in step with [onSchedule].
class EveryDays extends ReleasePattern {
  const EveryDays(this.days, this.onSchedule);

  final int days;
  final DateTime onSchedule;

  @override
  DateTime nextAfter(DateTime date) =>
      addDays(date, days - mod(daysBetween(onSchedule, date), days));

  @override
  DateTime previousBefore(DateTime date) =>
      addDays(date, -(mod(daysBetween(onSchedule, date) - 1, days) + 1));
}

class Weekdays extends ReleasePattern {
  const Weekdays(this.days);

  final Set<int> days;

  @override
  DateTime nextAfter(DateTime date) {
    var next = addDays(date, 1);
    while (!days.contains(next.weekday)) {
      next = addDays(next, 1);
    }
    return next;
  }

  @override
  DateTime previousBefore(DateTime date) {
    var prev = addDays(date, -1);
    while (!days.contains(prev.weekday)) {
      prev = addDays(prev, -1);
    }
    return prev;
  }

  // A release between close release days reads as an extra, not an early one.
  @override
  DateTime nearest(DateTime date) => date;
}

/// Releases for [length] days in a row, every [every] days in step with [onSchedule].
class Batches extends ReleasePattern {
  const Batches(this.every, this.onSchedule, this.length);

  final int every;
  final DateTime onSchedule;
  final int length;

  @override
  DateTime nextAfter(DateTime date) {
    final offset = mod(daysBetween(onSchedule, date), every);
    return addDays(date, offset + 1 < length ? 1 : every - offset);
  }

  @override
  DateTime previousBefore(DateTime date) {
    final dayBefore = addDays(date, -1);
    final offset = mod(daysBetween(onSchedule, dayBefore), every);
    return addDays(dayBefore, -max(offset - length + 1, 0));
  }
}

/// A pattern that repeats every month.
sealed class Monthly extends ReleasePattern {
  const Monthly();

  /// The release days in the month starting on [firstOfMonth].
  List<DateTime> daysIn(DateTime firstOfMonth);

  @override
  DateTime nextAfter(DateTime date) {
    var first = DateTime(date.year, date.month, 1);
    while (true) {
      final days = daysIn(first)..sort();
      for (final day in days) {
        if (day.isAfter(date)) return day;
      }
      first = DateTime(first.year, first.month + 1, 1);
    }
  }

  @override
  DateTime previousBefore(DateTime date) {
    var first = DateTime(date.year, date.month, 1);
    while (true) {
      final days = daysIn(first)..sort((a, b) => b.compareTo(a));
      for (final day in days) {
        if (day.isBefore(date)) return day;
      }
      first = DateTime(first.year, first.month - 1, 1);
    }
  }
}

/// Releases on [days] of every month, or a month's last day for those past it.
class DaysOfMonth extends Monthly {
  const DaysOfMonth(this.days);

  final Set<int> days;

  @override
  List<DateTime> daysIn(DateTime firstOfMonth) {
    final lastDay = addDays(
      DateTime(firstOfMonth.year, firstOfMonth.month + 1, 1),
      -1,
    ).day;
    return {
      for (final day in days)
        DateTime(
          firstOfMonth.year,
          firstOfMonth.month,
          min(day, lastDay),
        ),
    }.toList();
  }
}

/// Releases on [dayOfWeek] of the [week]th week of every month, or its last week for [lastWeek].
class WeekdayOfMonth extends Monthly {
  const WeekdayOfMonth(this.week, this.dayOfWeek);

  static const int lastWeek = -1;

  final int week;
  final int dayOfWeek;

  @override
  List<DateTime> daysIn(DateTime firstOfMonth) {
    if (week == lastWeek) {
      final lastOfMonth = addDays(
        DateTime(firstOfMonth.year, firstOfMonth.month + 1, 1),
        -1,
      );
      return [
        addDays(lastOfMonth, -mod(lastOfMonth.weekday - dayOfWeek, 7)),
      ];
    }
    return [
      addDays(
        firstOfMonth,
        mod(dayOfWeek - firstOfMonth.weekday, 7) + (week - 1) * 7,
      ),
    ];
  }
}

ReleasePattern? _monthly(List<DateTime> days) {
  final daysOfMonth = [for (final day in days) day.day];
  final spread = daysOfMonth.reduce(max) - daysOfMonth.reduce(min);
  if (spread <= _dayOfMonthTolerance) {
    return DaysOfMonth({medianOf(daysOfMonth)});
  }
  if (daysOfMonth.every((day) => day >= 28)) {
    return const DaysOfMonth({31});
  }
  return _weekdayOfMonth(days);
}

ReleasePattern? _weekdayOfMonth(List<DateTime> days) {
  final dayOfWeek = _mostCommon(days, (day) => day.weekday);
  if (dayOfWeek == null) return null;
  final week = _mostCommon(days, (day) => (day.day - 1) ~/ 7 + 1);
  if (week != null && week < 5) return WeekdayOfMonth(week, dayOfWeek);
  final lastWeekCount = days
      .where(
        (day) =>
            day.day + 7 >
            addDays(DateTime(day.year, day.month + 1, 1), -1).day,
      )
      .length;
  if (lastWeekCount >= days.length * _coverage) {
    return WeekdayOfMonth(WeekdayOfMonth.lastWeek, dayOfWeek);
  }
  return null;
}

ReleasePattern? _twiceMonthly(List<DateTime> days) {
  final daysOfMonth = [for (final day in days) day.day]..sort();
  var split = 1;
  for (var i = 2; i < daysOfMonth.length; i++) {
    if (daysOfMonth[i] - daysOfMonth[i - 1] >
        daysOfMonth[split] - daysOfMonth[split - 1]) {
      split = i;
    }
  }
  final halves = [
    daysOfMonth.sublist(0, split),
    daysOfMonth.sublist(split),
  ];
  if (halves.any(
    (half) =>
        half.length < 2 ||
        half.last - half.first > _dayOfMonthTolerance,
  )) {
    return null;
  }
  return DaysOfMonth({for (final half in halves) medianOf(half)});
}

ReleasePattern? _weekdays(List<DateTime> days, int medianGap) {
  final counts = <int, int>{};
  final firstSeen = <int, int>{};
  for (final day in days) {
    firstSeen.putIfAbsent(day.weekday, () => firstSeen.length);
    counts.update(day.weekday, (count) => count + 1, ifAbsent: () => 1);
  }
  final byFrequency = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0
          ? byCount
          : firstSeen[a.key]!.compareTo(firstSeen[b.key]!);
    });
  final weekdays = <int>{};
  var covered = 0;
  for (final entry in byFrequency) {
    if (covered >= days.length * _coverage) break;
    weekdays.add(entry.key);
    covered += entry.value;
  }
  if (weekdays.length < 2 ||
      weekdays.length > _maxWeekdays ||
      covered < days.length * _coverage) {
    return null;
  }
  if (medianGap > 7 ~/ weekdays.length + 1) return null;
  return Weekdays(weekdays);
}

ReleasePattern? _batches(List<DateTime> history) {
  final runs = <List<DateTime>>[];
  for (final day in history.take(_batchHistory).toList().reversed) {
    final run = runs.isNotEmpty ? runs.last : null;
    if (run != null && daysBetween(run.last, day) <= _batchGap) {
      run.add(day);
    } else {
      runs.add([day]);
    }
  }
  final recent = runs.length > _recentBatchRuns
      ? runs.sublist(runs.length - _recentBatchRuns)
      : runs;
  if (recent.length < _minBatches ||
      recent.where((run) => run.length > 1).length * 2 < recent.length) {
    return null;
  }
  final gaps = [
    for (var i = 0; i < recent.length - 1; i++)
      daysBetween(recent[i].first, recent[i + 1].first),
  ];
  final every = medianOf(gaps);
  final length = medianOf([
    for (final run in recent) daysBetween(run.first, run.last) + 1,
  ]);
  if (every < length * 2 ||
      gaps.any((gap) => (gap - every).abs() > every ~/ 4)) {
    return null;
  }
  return Batches(every, recent.last.first, length);
}

T? _mostCommon<T>(List<DateTime> days, T Function(DateTime) select) {
  final counts = <T, int>{};
  final order = <T>[];
  for (final day in days) {
    final key = select(day);
    if (!counts.containsKey(key)) order.add(key);
    counts.update(key, (count) => count + 1, ifAbsent: () => 1);
  }
  var best = order.first;
  for (final key in order) {
    if (counts[key]! > counts[best]!) best = key;
  }
  return counts[best]! >= days.length * _coverage ? best : null;
}
