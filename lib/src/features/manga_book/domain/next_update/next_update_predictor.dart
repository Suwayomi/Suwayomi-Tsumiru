// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

const int kMaxFetchIntervalDays = 28;

/// One chapter's relevant timestamps, epoch milliseconds (0 = absent).
typedef ChapterRelease = ({int uploadMs, int fetchMs});

/// [nextUpdate] is null when there is no usable date history.
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

/// Uses median upload-day gaps, then fetch-day gaps, else 7 days; clamps to 1..28 and projects whole cycles forward.
NextUpdatePrediction predictNextUpdate(
  List<ChapterRelease> chapters, {
  DateTime? now,
}) {
  final interval = _calculateInterval(chapters);

  final latestDate = _latestReleaseStartOfDay(chapters);
  if (latestDate == null) {
    return NextUpdatePrediction(intervalDays: interval, nextUpdate: null);
  }

  final nowTime = now ?? DateTime.now();
  final timeSinceLatest = math.max(0, nowTime.difference(latestDate).inDays);
  final cycle =
      timeSinceLatest ~/ _increaseInterval(interval, timeSinceLatest, 10);
  return NextUpdatePrediction(
    intervalDays: interval,
    nextUpdate: latestDate.add(Duration(days: (cycle + 1) * interval)),
  );
}

/// Widen overdue intervals up to 28 days to avoid imminent predictions for dormant series.
int _increaseInterval(int delta, int timeSinceLatest, int increaseWhenOver) {
  if (delta >= kMaxFetchIntervalDays) return kMaxFetchIntervalDays;
  final cycle = (timeSinceLatest ~/ delta) + 1;
  return cycle > increaseWhenOver
      ? _increaseInterval(delta * 2, timeSinceLatest, increaseWhenOver)
      : delta;
}

int _calculateInterval(List<ChapterRelease> chapters) {
  // Wider sampling window once there's a decent backlog (3 vs 10).
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

/// Recent distinct days, newest first, ignoring absent timestamps (<= 0).
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

/// Uses the lower median; fewer than three distinct days gives no estimate.
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
    for (final c in chapters) {
      if (c.fetchMs > latest) latest = c.fetchMs;
    }
  }
  if (latest == 0) return null;
  final d = DateTime.fromMillisecondsSinceEpoch(latest);
  return DateTime(d.year, d.month, d.day);
}
