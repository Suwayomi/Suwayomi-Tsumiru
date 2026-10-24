// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

library;

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

  /// Missing or obsolete extensions put the source in "Needs migration".
  final bool isObsolete;
}

typedef MangaSourceInfo = ({
  String sourceId,
  String displayName,
  bool isObsolete,
});

/// Groups by source ID alphabetically; any obsolete or missing extension marks its source obsolete.
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
