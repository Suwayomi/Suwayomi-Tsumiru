// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../../library/domain/duplicate_entry_mapper.dart';
import '../../../../library/domain/duplicate_matcher.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../../manga_book/presentation/manga_details/widgets/duplicate_manga_dialog.dart';

/// The result of splitting a bulk selection into what can be added silently and
/// what needs a per-entry duplicate prompt.
///
/// [hitIdsByManga] / [certainIdsByManga] key on the *selected* manga id and hold
/// the ids of the entries it collided with — those ids may reference the library
/// OR an earlier selection member, so the widget resolves card DTOs from the
/// union of both.
typedef BulkSplit = ({
  List<int> cleanIds,
  List<MangaDto> flagged,
  Map<int, Set<int>> hitIdsByManga,
  Map<int, Set<int>> certainIdsByManga,
});

/// Classifies each selected manga against the library plus every earlier
/// selection member already ruled clean (Komikku's incremental semantics — the
/// second of two identical picks is caught by the first). A null [library]
/// (provider error) fails open: everything is treated as clean.
BulkSplit splitSelectionForDuplicates({
  required List<MangaDto> selection,
  required List<MangaDto>? library,
}) {
  if (library == null) {
    return (
      cleanIds: selection.map((m) => m.id).toList(),
      flagged: const [],
      hitIdsByManga: const {},
      certainIdsByManga: const {},
    );
  }

  final cleanIds = <int>[];
  final flagged = <MangaDto>[];
  final hitIdsByManga = <int, Set<int>>{};
  final certainIdsByManga = <int, Set<int>>{};

  // Comparators grow as clean members are accepted, so a later pick collides
  // with an earlier clean one. Flagged members never join the pool.
  final pool = library.map(dupEntryFromManga).toList();

  for (final manga in selection) {
    final candidate = dupEntryFromManga(manga);
    final titleHits = titleDuplicates(
      candidateId: manga.id,
      candidateTitle: manga.title,
      entries: pool,
    );
    final trackerHits = trackerDuplicates(
      candidateId: manga.id,
      candidatePairs: candidate.trackerPairs,
      entries: pool,
    );
    final hitIds = {
      ...titleHits.map((e) => e.id),
      ...trackerHits.map((e) => e.id),
    };
    if (hitIds.isEmpty) {
      cleanIds.add(manga.id);
      pool.add(candidate);
    } else {
      flagged.add(manga);
      hitIdsByManga[manga.id] = hitIds;
      certainIdsByManga[manga.id] = trackerHits.map((e) => e.id).toSet();
    }
  }

  return (
    cleanIds: cleanIds,
    flagged: flagged,
    hitIdsByManga: hitIdsByManga,
    certainIdsByManga: certainIdsByManga,
  );
}

/// What the bulk loop does with one duplicate prompt's result.
enum BulkDupAction {
  addThis,
  addRest,
  skipThis,
  skipRest,
  handled,
  openStop,
  cancelStop,
}

/// Maps a [DuplicateDialogResult] to its bulk-loop action. The exhaustive switch
/// (no `default:`, null handled) is the compile-time guarantee that every dialog
/// outcome — including a barrier dismiss (null) — has a defined behavior.
BulkDupAction classifyDuplicateResult(DuplicateDialogResult? result) =>
    switch (result) {
      DuplicateDialogResult.addAnyway => BulkDupAction.addThis,
      DuplicateDialogResult.allowAll => BulkDupAction.addRest,
      DuplicateDialogResult.skipIt => BulkDupAction.skipThis,
      DuplicateDialogResult.skipAll => BulkDupAction.skipRest,
      DuplicateDialogResult.migrated => BulkDupAction.handled,
      DuplicateDialogResult.openedEntry => BulkDupAction.openStop,
      DuplicateDialogResult.cancel => BulkDupAction.cancelStop,
      null => BulkDupAction.cancelStop,
    };
