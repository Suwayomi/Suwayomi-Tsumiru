// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

// Leading dot prevents parsing the manifest as a page index.
const String kChapterManifestName = '.manifest';

/// Defines completeness before the first page is written; catalog pageCount can change during sync.
/// Commit rejects a generation that no longer matches the catalog.
class ChapterManifest {
  const ChapterManifest({required this.generation, required this.indices});

  final int generation;

  /// Explicit indices let resumed downloads identify missing pages, not just a missing count.
  final List<int> indices;

  int get pageCount => indices.length;

  Map<String, Object?> toJson() => {'gen': generation, 'idx': indices};

  String toJsonString() => jsonEncode(toJson());

  static ChapterManifest? tryParse(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final indices = json['idx'];
      if (indices is! List) return null;
      return ChapterManifest(
        generation: (json['gen'] as num?)?.toInt() ?? 0,
        indices: [for (final i in indices) (i as num).toInt()],
      );
    } catch (_) {
      return null;
    }
  }

  /// A changed page set requires discarding existing staging.
  bool coversSameIndices(Iterable<int> other) {
    final want = other.toSet();
    return want.length == indices.length && want.containsAll(indices);
  }
}
