// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'release_pattern.dart';

const int kMaxFetchIntervalDays = 28;

const int _defaultInterval = 7;
const int _hiatusCycles = 4;
const int _minReleases = 3;
const int _fewChapters = 8;
const int _fewChaptersReleases = 3;
const int _recentReleases = 10;
const int _phaseReleases = 5;

/// One chapter's relevant timestamps, epoch milliseconds (0 = absent).
typedef ChapterRelease = ({int uploadMs, int fetchMs});

/// [nextUpdate] is null when there is no usable date history.
class NextUpdatePrediction {
  const NextUpdatePrediction({required this.intervalDays, this.nextUpdate});

  final int intervalDays;
  final DateTime? nextUpdate;

  /// Whole calendar days from [now] until the next expected chapter, floored at 0.
  /// Null when there's no prediction.
  int? daysUntil(DateTime now) {
    final next = nextUpdate;
    if (next == null) return null;
    return math.max(
      0,
      daysBetween(startOfDay(now), startOfDay(next)),
    );
  }
}

/// Estimates the release schedule from chapter dates, then reads the next check off it.
NextUpdatePrediction predictNextUpdate(
  List<ChapterRelease> chapters, {
  DateTime? now,
}) {
  final today = startOfDay(now ?? DateTime.now());
  final schedule = ReleaseSchedule.estimate(chapters, today);
  if (schedule.lastRelease == null) {
    return NextUpdatePrediction(
      intervalDays: schedule.interval,
      nextUpdate: null,
    );
  }
  return NextUpdatePrediction(
    intervalDays: schedule.interval,
    nextUpdate: schedule.nextCheck(today),
  );
}

/// How often an entry releases, and so when to check it for the next release.
class ReleaseSchedule {
  const ReleaseSchedule({
    required this.interval,
    required this.lastRelease,
    required this.pattern,
    this.lateness = 0,
    this.backsOff = true,
    this.pastBreaks = const [],
  });

  /// Days between releases, which is what the fetch interval shows.
  final int interval;

  /// The most recent release day, which the next ones are counted from.
  final DateTime? lastRelease;

  final ReleasePattern pattern;

  /// Days past the expected day a release can still come, from how late recent ones were.
  final int lateness;

  final bool backsOff;

  /// Lengths in days of earlier breaks, which a break like a season's end is expected to last again.
  final List<int> pastBreaks;

  /// The next day to check for a release, as of [today].
  DateTime nextCheck(DateTime today) {
    final anchor = lastRelease ?? today;
    final daysSinceRelease = daysBetween(anchor, today);
    final isOnBreak =
        backsOff && daysSinceRelease > interval * _hiatusCycles;
    if (isOnBreak &&
        pastBreaks.every(
          (past) =>
              daysSinceRelease < past - interval ||
              daysSinceRelease > past + interval,
        )) {
      final backedOff = _backOff(daysSinceRelease);
      final next = addDays(
        anchor,
        ceilDiv(daysSinceRelease, backedOff) * backedOff,
      );
      DateTime? breakEnd;
      for (final past in pastBreaks) {
        final end = addDays(anchor, past - interval);
        if (end.isAfter(today) &&
            (breakEnd == null || end.isBefore(breakEnd))) {
          breakEnd = end;
        }
      }
      if (breakEnd != null && breakEnd.isBefore(next)) return breakEnd;
      return next;
    }

    final due = pattern.nextAfter(pattern.nearest(anchor));
    if (!today.isBefore(due) &&
        !today.isAfter(addDays(due, lateness))) {
      return today;
    }
    var next = due;
    while (next.isBefore(today)) {
      next = pattern.nextAfter(next);
    }
    final cap = addDays(today, kMaxFetchIntervalDays);
    return next.isBefore(cap) ? next : cap;
  }

  int _backOff(int daysSinceRelease) {
    var backedOff = interval;
    while (backedOff < kMaxFetchIntervalDays &&
        daysSinceRelease > backedOff * _hiatusCycles) {
      backedOff *= 2;
    }
    return math.min(backedOff, kMaxFetchIntervalDays);
  }

  /// Estimates the schedule from the recent release days of [chapters], by upload date or else fetch date.
  static ReleaseSchedule estimate(
    List<ChapterRelease> chapters,
    DateTime today,
  ) {
    final maxReleases =
        chapters.length <= _fewChapters ? _fewChaptersReleases : _recentReleases;
    // Future-dated chapters would otherwise pull the schedule into the future.
    final latestPlausibleDay = addDays(today, 1);

    List<DateTime> releaseDays(Iterable<int> stamps) {
      final seen = <int>{};
      final days = <DateTime>[];
      for (final stamp in stamps) {
        if (stamp <= 0) continue;
        final date = DateTime.fromMillisecondsSinceEpoch(stamp);
        final day = DateTime(date.year, date.month, date.day);
        if (day.isAfter(latestPlausibleDay)) continue;
        if (seen.add(day.millisecondsSinceEpoch)) days.add(day);
      }
      days.sort((a, b) => b.compareTo(a));
      return days;
    }

    final uploadDays =
        releaseDays([for (final chapter in chapters) chapter.uploadMs]);
    final fetchDays =
        releaseDays([for (final chapter in chapters) chapter.fetchMs]);
    final List<DateTime>? history = uploadDays.length >= _minReleases
        ? uploadDays
        : (fetchDays.length >= _minReleases ? fetchDays : null);
    if (history == null) {
      final lastRelease = uploadDays.isNotEmpty
          ? uploadDays.first
          : (fetchDays.isNotEmpty ? fetchDays.first : null);
      return ReleaseSchedule(
        interval: _defaultInterval,
        lastRelease: lastRelease,
        pattern: EveryDays(_defaultInterval, lastRelease ?? today),
      );
    }
    final days = history.take(maxReleases).toList();

    final gaps = [
      for (var i = 0; i < days.length - 1; i++)
        daysBetween(days[i + 1], days[i]),
    ]..sort();
    final medianGap = gaps[(gaps.length - 1) ~/ 2];
    final detected = ReleasePattern.detect(
      days: days,
      history: history,
      medianGap: medianGap,
    );
    final every = detected is Batches ? detected.every : medianGap;
    final interval = every.clamp(1, kMaxFetchIntervalDays);
    return ReleaseSchedule(
      interval: interval,
      lastRelease: days.first,
      pattern: detected ??
          EveryDays(interval, _medianPhase(days.take(_phaseReleases).toList(), interval)),
      lateness: (gaps.last - interval).clamp(0, interval ~/ 2),
      pastBreaks: [
        for (var i = 0; i < history.length - 1; i++)
          daysBetween(history[i + 1], history[i]),
      ].where((gap) => gap > interval * _hiatusCycles).toList(),
    );
  }

  static DateTime _medianPhase(List<DateTime> days, int interval) {
    int offset(DateTime from, DateTime to) {
      final remainder = mod(daysBetween(from, to), interval);
      return math.min(remainder, interval - remainder);
    }

    var phase = days.first;
    var bestScore = days.fold<int>(
      0,
      (score, day) => score + offset(phase, day),
    );
    for (final candidate in days) {
      final score = days.fold<int>(
        0,
        (score, day) => score + offset(candidate, day),
      );
      if (score < bestScore) {
        phase = candidate;
        bestScore = score;
      }
    }
    final onPhase =
        days.where((day) => offset(phase, day) == 0).length;
    return onPhase * 5 >= days.length * 3 ? phase : days.first;
  }
}
