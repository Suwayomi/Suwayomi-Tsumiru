// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';

import '../../../library/domain/library_search_query.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../manga_book/domain/manga/manga_model.dart';

const int kUnifiedSectionLimit = 6;

bool queryUsesOperator(String q) => LibrarySearchQuery.hasOperator(q);

/// Removes local metatag operators before sending plain text to a source search.
String plainQueryText(String q) => LibrarySearchQuery.plainText(q);

final unifiedSearchQueryProvider = StateProvider<String>((Ref ref) => '');

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

int countLibraryTitles<T>(
  List<T> items,
  String query,
  bool Function(T item, String query) matches,
) {
  if (query.trim().isEmpty) return 0;
  var count = 0;
  for (final item in items) {
    if (matches(item, query)) count++;
  }
  return count;
}

bool titleMatchesQuery(String title, String query) =>
    title.toLowerCase().contains(query.trim().toLowerCase());

/// Plain words match titles only; metatag queries use the full library DSL.
final unifiedLibraryResultsForProvider = Provider.autoDispose
    .family<List<MangaDto>, String>((Ref ref, String query) {
      final library = ref.watch(libraryMangaListProvider).value ?? const [];
      final useDsl = queryUsesOperator(query);
      return matchLibraryTitles<MangaDto>(
        library,
        query,
        (m, q) => useDsl ? m.query(q) : titleMatchesQuery(m.title, q),
      );
    });

final unifiedLibraryResultCountForProvider = Provider.autoDispose
    .family<int, String>((Ref ref, String query) {
      final library = ref.watch(libraryMangaListProvider).value ?? const [];
      final useDsl = queryUsesOperator(query);
      return countLibraryTitles<MangaDto>(
        library,
        query,
        (m, q) => useDsl ? m.query(q) : titleMatchesQuery(m.title, q),
      );
    });

final unifiedLibraryResultsProvider = Provider<List<MangaDto>>(
  (Ref ref) => ref.watch(
    unifiedLibraryResultsForProvider(ref.watch(unifiedSearchQueryProvider)),
  ),
);
