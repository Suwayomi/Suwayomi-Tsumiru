// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

/// Maximum predicted interval, in days (Komikku `FetchInterval.MAX_INTERVAL`).
const int kMaxFetchIntervalDays = 28;

/// One chapter's relevant timestamps, epoch milliseconds (0 = absent).
typedef ChapterRelease = ({int uploadMs, int fetchMs});

/// Result of [predictNextUpdate]: the estimated release [intervalDays] and the
/// projected [nextUpdate] (null when there's no usable date history).
class NextUpdatePrediction {
  const NextUpdatePrediction({required this.intervalDays, this.nextUpdate});

  final int intervalDays;
  final DateTime? nextUpdate;

  /// Whole days from [now] until the next expected chapter, floored at 0.
  /// Null when there's no prediction.
  int? daysUntil(DateTime now) {
    final next = nextUpdate;
    if (next == null) return null;
    return math.max(0, next.difference(now).inDays);
  }
}

/// Predict when a manga's next chapter is due, from its own release history.
///
/// The release [intervalDays] is computed exactly like Komikku/Mihon
/// `tachiyomi.domain.manga.interactor.FetchInterval.calculateInterval`: the
/// median gap between recent distinct release days (upload dates, falling back
/// to fetch dates, else a 7-day default), clamped to 1..28 days.
///
/// The next date is simply `latestRelease + interval`. (Komikku projects
/// forward whole cycles, but that only ever reads "Soon" because it *stores*
/// the value and counts down to a stale one; computed live, latest+interval
/// gives the intended "In N days" while pending and "Soon" once due/overdue.)
NextUpdatePrediction predictNextUpdate(
  List<ChapterRelease> chapters, {
  DateTime? now,
}) {
  final interval = _calculateInterval(chapters);

  final latestDate = _latestReleaseStartOfDay(chapters);
  if (latestDate == null) {
    // No dated chapters at all → no estimate.
    return NextUpdatePrediction(intervalDays: interval, nextUpdate: null);
  }

  return NextUpdatePrediction(
    intervalDays: interval,
    nextUpdate: latestDate.add(Duration(days: interval)),
  );
}

int _calculateInterval(List<ChapterRelease> chapters) {
  // Wider sampling window once there's a decent backlog (Komikku: 3 vs 10).
  final window = chapters.length <= 8 ? 3 : 10;

  final uploadDays = _recentDistinctDays(
    chapters,
    (c) => c.uploadMs,
    window,
  );
  final fetchDays = _recentDistinctDays(
    chapters,
    (c) => c.fetchMs,
    window,
  );

  final fromUpload = _medianGapDays(uploadDays);
  final fromFetch = _medianGapDays(fetchDays);

  final interval = fromUpload ?? fromFetch ?? 7;
  return interval.clamp(1, kMaxFetchIntervalDays);
}

/// Most recent [window] distinct release days (start-of-day, descending) for a
/// given timestamp, ignoring absent (<= 0) values.
List<DateTime> _recentDistinctDays(
  List<ChapterRelease> chapters,
  int Function(ChapterRelease) pick,
  int window,
) {
  final sorted = [...chapters]..sort((a, b) => pick(b).compareTo(pick(a)));
  final seen = <int>{};
  final days = <DateTime>[];
  for (final c in sorted) {
    final ms = pick(c);
    if (ms <= 0) continue;
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final startOfDay = DateTime(d.year, d.month, d.day);
    if (seen.add(startOfDay.millisecondsSinceEpoch)) {
      days.add(startOfDay);
      if (days.length >= window) break;
    }
  }
  return days;
}

/// Median gap (days) between consecutive [days] (descending). Needs >= 3 days
/// (i.e. >= 2 gaps) to be meaningful; null otherwise. Matches Komikku's
/// `ranges[(ranges.size - 1) / 2]` lower-median.
int? _medianGapDays(List<DateTime> days) {
  if (days.length < 3) return null;
  final gaps = <int>[
    for (var i = 0; i < days.length - 1; i++) days[i].difference(days[i + 1]).inDays,
  ]..sort();
  return gaps[(gaps.length - 1) ~/ 2];
}

DateTime? _latestReleaseStartOfDay(List<ChapterRelease> chapters) {
  var latest = 0;
  for (final c in chapters) {
    if (c.uploadMs > latest) latest = c.uploadMs;
  }
  if (latest == 0) {
    // No upload dates — fall back to the newest fetch date.
    for (final c in chapters) {
      if (c.fetchMs > latest) latest = c.fetchMs;
    }
  }
  if (latest == 0) return null;
  final d = DateTime.fromMillisecondsSinceEpoch(latest);
  return DateTime(d.year, d.month, d.day);
}
