// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../manga_book/domain/manga/manga_model.dart';

const int kUnifiedSectionLimit = 6;

/// The live query text in the unified search field.
final unifiedSearchQueryProvider = StateProvider<String>((ref) => '');

/// Generic, testable filter+cap over a list, using an injected predicate.
/// Extracted so the matching/cap rule is unit-testable without GraphQL DTOs.
List<T> matchLibraryTitles<T>(
  List<T> items,
  String query,
  bool Function(T item, String query) matches,
) {
  if (query.trim().isEmpty) return const [];
  final out = <T>[];
  for (final item in items) {
    if (matches(item, query)) {
      out.add(item);
      if (out.length >= kUnifiedSectionLimit) break;
    }
  }
  return out;
}

/// Quick search matches the TITLE only. The library DSL (`MangaDto.query`)
/// also matches author/genre/description/tags, which surfaces confusing hits
/// like "bad" → a manga whose description mentions "bad".
bool titleMatchesQuery(String title, String query) =>
    title.toLowerCase().contains(query.trim().toLowerCase());

/// Top matching in-library manga for the current query (instant, local).
final unifiedLibraryResultsProvider = Provider<List<MangaDto>>((ref) {
  final query = ref.watch(unifiedSearchQueryProvider);
  final library = ref.watch(libraryMangaListProvider).valueOrNull ?? const [];
  return matchLibraryTitles<MangaDto>(
    library,
    query,
    (m, q) => titleMatchesQuery(m.title, q),
  );
});
