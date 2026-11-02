// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';

enum TrackStatus {
  reading('Reading'),
  repeating('Rereading'),
  planToRead('Plan to read'),
  paused('On hold'),
  completed('Completed'),
  dropped('Dropped'),
  other('Other');

  const TrackStatus(this.label);

  final String label;
}

const int _myAnimeListTrackerId = 1;
const int _aniListTrackerId = 2;
const int _kitsuTrackerId = 3;
const int _shikimoriTrackerId = 4;
const int _bangumiTrackerId = 5;
const int _mangaUpdatesTrackerId = 7;
const int _mangaBakaTrackerId = 11;

TrackStatus parseTrackerStatus(int trackerId, int status) => switch (trackerId) {
  _myAnimeListTrackerId => switch (status) {
    1 => TrackStatus.reading,
    2 => TrackStatus.completed,
    3 => TrackStatus.paused,
    4 => TrackStatus.dropped,
    6 => TrackStatus.planToRead,
    7 => TrackStatus.repeating,
    _ => TrackStatus.other,
  },
  _aniListTrackerId || _shikimoriTrackerId => switch (status) {
    1 => TrackStatus.reading,
    2 => TrackStatus.completed,
    3 => TrackStatus.paused,
    4 => TrackStatus.dropped,
    5 => TrackStatus.planToRead,
    6 => TrackStatus.repeating,
    _ => TrackStatus.other,
  },
  _mangaBakaTrackerId => switch (status) {
    1 => TrackStatus.reading,
    2 => TrackStatus.completed,
    3 => TrackStatus.paused,
    4 => TrackStatus.dropped,
    5 || 7 => TrackStatus.planToRead,
    6 => TrackStatus.repeating,
    _ => TrackStatus.other,
  },
  _kitsuTrackerId => switch (status) {
    1 => TrackStatus.reading,
    2 => TrackStatus.completed,
    3 => TrackStatus.paused,
    4 => TrackStatus.dropped,
    5 => TrackStatus.planToRead,
    _ => TrackStatus.other,
  },
  _bangumiTrackerId => switch (status) {
    2 => TrackStatus.completed,
    4 => TrackStatus.paused,
    5 => TrackStatus.dropped,
    1 => TrackStatus.planToRead,
    _ => TrackStatus.reading,
  },
  _mangaUpdatesTrackerId => switch (status) {
    0 => TrackStatus.reading,
    2 => TrackStatus.completed,
    4 => TrackStatus.paused,
    3 => TrackStatus.dropped,
    1 => TrackStatus.planToRead,
    _ => TrackStatus.other,
  },
  _ => TrackStatus.other,
};


/// Converts to a 0–10 scale; nonpositive [scaleMax] returns 0.
/// [scaleMax] is the numeric last tracker score label, e.g. 9.9 for MangaUpdates.
double normalizedScore({required double score, required double scaleMax}) {
  if (scaleMax <= 0) return 0;
  return (score / scaleMax) * 10.0;
}

/// Mean normalized score; missing scales default to 10.0.
/// Empty [nodes] returns -1.0, which callers must sort last in either direction.
double meanNormalizedScore(
  List<Fragment$MangaDto$trackRecords$nodes> nodes, {
  required Map<int, double> trackerScales,
}) {
  if (nodes.isEmpty) return -1.0;

  double sum = 0;
  for (final node in nodes) {
    final scale = trackerScales[node.trackerId] ?? 10.0;
    sum += normalizedScore(score: node.score, scaleMax: scale);
  }
  return sum / nodes.length;
}
