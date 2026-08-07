// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Groups the library by source for the "a source died, move everything off it"
/// picker. Pure — no GraphQL/Riverpod — so the obsolete-first ordering is
/// unit-testable.
library;

/// One library source with its entry count and whether it needs migration.
class LibrarySourceGroup {
  const LibrarySourceGroup({
    required this.sourceId,
    required this.displayName,
    required this.count,
    required this.isObsolete,
  });

  final String sourceId;
  final String displayName;
  final int count;

  /// The source's extension is obsolete OR uninstalled/missing — its manga can
  /// no longer update, so it's floated to the top under "Needs migration".
  final bool isObsolete;
}

/// Per-manga source facts the grouper needs.
typedef MangaSourceInfo = ({
  String sourceId,
  String displayName,
  bool isObsolete,
});

/// Groups [mangas] by source id and counts each, sorted alphabetically. A
/// source is obsolete if ANY of its entries reports it so (a null/uninstalled
/// extension counts as obsolete); the picker screen offers an obsolete FILTER
/// and its own sort mode/direction (Komikku parity), so this is only the base
/// grouping.
List<LibrarySourceGroup> groupLibraryBySource(List<MangaSourceInfo> mangas) {
  final byId = <String, ({String name, bool obsolete, int count})>{};
  for (final m in mangas) {
    final prev = byId[m.sourceId];
    byId[m.sourceId] = (
      name: prev?.name ?? m.displayName,
      obsolete: (prev?.obsolete ?? false) || m.isObsolete,
      count: (prev?.count ?? 0) + 1,
    );
  }
  final groups = [
    for (final e in byId.entries)
      LibrarySourceGroup(
        sourceId: e.key,
        displayName: e.value.name,
        count: e.value.count,
        isObsolete: e.value.obsolete,
      ),
  ];
  groups.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  return groups;
}
