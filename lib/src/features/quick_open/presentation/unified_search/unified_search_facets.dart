// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../library/domain/library_search_query.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../manga_book/domain/manga/manga_model.dart';

/// Distinct values present in the library for each enumerable metatag, used to
/// power value-autocomplete (`source:` → the sources you actually have). Only
/// enumerable operators appear here; booleans and `rating:` are handled by the
/// autocomplete engine directly.
class LibraryFacets {
  const LibraryFacets({
    this.source = const [],
    this.status = const [],
    this.genre = const [],
    this.tag = const [],
    this.author = const [],
    this.artist = const [],
  });

  final List<String> source;
  final List<String> status;
  final List<String> genre;
  final List<String> tag;
  final List<String> author;
  final List<String> artist;

  static const empty = LibraryFacets();

  /// Values to suggest for metatag [key], or null when the key has no
  /// enumerable facet (free-form numeric/boolean).
  List<String>? valuesFor(String key) => switch (key) {
        'source' => source,
        'status' => status,
        'genre' => genre,
        'tag' => tag,
        'author' => author,
        'artist' => artist,
        _ => null,
      };
}

/// Builds [LibraryFacets] from the flat field views of the library. Pure so it
/// unit-tests without GraphQL DTOs; status is lowercased for display.
LibraryFacets buildLibraryFacets(Iterable<LibraryFilterFields> fields) {
  final source = <String>{};
  final status = <String>{};
  final genre = <String>{};
  final tag = <String>{};
  final author = <String>{};
  final artist = <String>{};

  void addTo(Set<String> set, String? value) {
    if (value != null && value.isNotEmpty) set.add(value);
  }

  for (final f in fields) {
    addTo(source, f.sourceName);
    addTo(status, f.status?.toLowerCase());
    addTo(author, f.author);
    addTo(artist, f.artist);
    for (final g in f.genres) {
      addTo(genre, g);
    }
    for (final t in f.userTags) {
      addTo(tag, t);
    }
  }

  List<String> sorted(Set<String> s) => s.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  return LibraryFacets(
    source: sorted(source),
    status: sorted(status),
    genre: sorted(genre),
    tag: sorted(tag),
    author: sorted(author),
    artist: sorted(artist),
  );
}

/// Library facets for autocomplete — recomputed only when the library changes,
/// not per keystroke.
final unifiedLibraryFacetsProvider = Provider<LibraryFacets>((Ref ref) {
  final library = ref.watch(libraryMangaListProvider).value ?? const [];
  return buildLibraryFacets(library.map((m) => m.filterFields()));
});
