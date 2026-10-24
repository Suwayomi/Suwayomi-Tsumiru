// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';

/// Status 0 is untracked and omitted by the server; unknown statuses use Other (99).
const Map<int, ({String label, int order})> kTrackStatusInfo = {
  1: (label: 'Reading', order: 1),
  2: (label: 'Completed', order: 2),
  3: (label: 'On hold', order: 3),
  4: (label: 'Dropped', order: 4),
  5: (label: 'Plan to read', order: 5),
  6: (label: 'Re-reading', order: 6),
};

/// Unknown values use "Other".
String trackStatusLabel(int status) =>
    kTrackStatusInfo[status]?.label ?? 'Other';

/// Unknown values sort last (99).
int trackStatusOrder(int status) => kTrackStatusInfo[status]?.order ?? 99;


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
