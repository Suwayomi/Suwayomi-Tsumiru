// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../library/domain/library_search_query.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../manga_book/domain/manga/manga_model.dart';

const int kUnifiedSectionLimit = 6;

/// Matches a recognized metatag operator (`source:`, `tag:`, `-status:`…) at a
/// term boundary — same shape the DSL highlighter uses. An unknown key like
/// `Re:Zero` is intentionally excluded so plain titles still search plainly.
final _operatorPattern = RegExp(
  '(^|[\\s,])(-?)(${librarySearchMetatagKeys.join('|')}):',
  caseSensitive: false,
);

/// Whether [q] should run through the full library DSL rather than title-only.
bool queryUsesOperator(String q) => _operatorPattern.hasMatch(q);

/// The plain-text portion of [q] with metatag operator tokens removed — what a
/// global *source* search should receive. Operators like `unread:true` are
/// local filters that make no sense against a source, so `unread:true` → ``,
/// `bad source:mangadex` → `bad`.
String plainQueryText(String q) {
  final kept = [
    for (final token in q.split(RegExp(r'[\s,]+')))
      if (token.isNotEmpty && !queryUsesOperator(token)) token,
  ];
  return kept.join(' ');
}

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
///
/// Hybrid: plain words match the TITLE only (keeps "bad" clean); the moment the
/// query contains a metatag operator it runs the full library DSL, so quick
/// search is never weaker than the library filter bar.
final unifiedLibraryResultsProvider = Provider<List<MangaDto>>((ref) {
  final query = ref.watch(unifiedSearchQueryProvider);
  final library = ref.watch(libraryMangaListProvider).valueOrNull ?? const [];
  final useDsl = queryUsesOperator(query);
  return matchLibraryTitles<MangaDto>(
    library,
    query,
    (m, q) => useDsl ? m.query(q) : titleMatchesQuery(m.title, q),
  );
});
