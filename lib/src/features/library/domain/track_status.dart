// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';

/// Track-status integer values and their display labels/sort order.
///
/// The server uses
/// small positive integers for status; the common set across MAL/AniList/Kitsu is:
///   1 = Reading
///   2 = Completed
///   3 = On-hold
///   4 = Dropped
///   5 = Plan to read
///   6 = Re-reading
///
/// Status 0 is "Not tracked" — the server omits nodes with status 0.
/// Anything outside the map falls back to order 99 ("Other").
const Map<int, ({String label, int order})> kTrackStatusInfo = {
  1: (label: 'Reading', order: 1),
  2: (label: 'Completed', order: 2),
  3: (label: 'On hold', order: 3),
  4: (label: 'Dropped', order: 4),
  5: (label: 'Plan to read', order: 5),
  6: (label: 'Re-reading', order: 6),
};

/// Label for [status]; falls back to "Other" for unknown values.
String trackStatusLabel(int status) =>
    kTrackStatusInfo[status]?.label ?? 'Other';

/// Sort order for [status]; unknown values sort last (99).
int trackStatusOrder(int status) => kTrackStatusInfo[status]?.order ?? 99;

// ─────────────────────── score normalization ─────────────────────────────────

/// Normalizes [score] on a [scaleMax] scale to a 0–10 value.
///
/// Divides the raw score by the tracker's max score and multiplies by 10.
///
/// [scaleMax] is the tracker-specific maximum score value, derived from the
/// numeric value of the last entry in `tracker.scores` (e.g. "9.9" → 9.9 for
/// MangaUpdates, "100" → 100.0 for AniList). See [libraryTrackerScalesProvider].
///
/// When [scaleMax] is 0 or negative, returns 0 to avoid division by zero.
double normalizedScore({required double score, required double scaleMax}) {
  if (scaleMax <= 0) return 0;
  return (score / scaleMax) * 10.0;
}

/// Returns the mean of [normalizedScore] across all [nodes].
///
/// Nodes whose tracker id is absent from [trackerScales] fall back to a
/// default scale of 10.0 (MAL-compatible — a safe assumption for unknown
/// trackers since most use 0-10).
///
/// Returns `-1.0` when [nodes] is empty — this sentinel causes the manga to
/// sort *last* regardless of sort direction, since actual scores are in [0, 10].
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
