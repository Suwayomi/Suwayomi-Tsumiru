// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

/// Filename of the manifest inside a chapter's staging directory. The leading
/// dot keeps it from ever parsing as a page index.
const String kChapterManifestName = '.manifest';

/// What a complete download of one chapter looks like, written into staging
/// before the first page lands.
///
/// This is the only thing on disk that knows how many pages a chapter should
/// have. The catalog's `pageCount` cannot serve: it defaults to 0 and a
/// metadata sync rewrites it from the server, so counting against it would
/// call a half-downloaded chapter complete.
///
/// [generation] is the chapter's download generation at the moment staging
/// opened. Commit refuses staging whose generation no longer matches the
/// catalog row, which is what stops a producer that outlived a delete from
/// publishing into a chapter the user has since removed or re-queued.
class ChapterManifest {
  const ChapterManifest({required this.generation, required this.indices});

  final int generation;

  /// The page indices this chapter consists of. Held explicitly rather than as
  /// a count because completeness is "one file per listed index" — a resumed
  /// download has to know which are still missing, not just how many.
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
      // Torn or hand-mangled — treat staging as unusable rather than guess at
      // a page set; the caller wipes and restarts.
      return null;
    }
  }

  /// True when [other] describes the same page set — a resolved page list that
  /// disagrees means the chapter changed under us and staging must be dropped.
  bool coversSameIndices(Iterable<int> other) {
    final want = other.toSet();
    return want.length == indices.length && want.containsAll(indices);
  }
}
