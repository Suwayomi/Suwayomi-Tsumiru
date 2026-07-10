// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

MangaDto _manga(int id, {int? rating}) => Fragment$MangaDto(
      id: id,
      title: 'M$id',
      bookmarkCount: 0,
      chapters: Fragment$MangaDto$chapters(totalCount: 0),
      downloadCount: 0,
      genre: const [],
      inLibrary: true,
      inLibraryAt: '0',
      initialized: true,
      meta: rating == null
          ? const []
          : [Fragment$MangaDto$meta(key: 'flutter_rating', value: '$rating')],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords:
          Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
      unreadCount: 0,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/$id',
    );

List<MangaDto> _run(
  List<MangaDto> input, {
  MangaSort sort = MangaSort.alphabetical,
  bool asc = true,
  int minRating = 0,
}) =>
    applyLibraryFilterSort(
      input,
      query: null,
      mangaFilterUnread: null,
      mangaFilterDownloaded: null,
      mangaFilterCompleted: null,
      mangaFilterStarted: null,
      mangaFilterBookmarked: null,
      mangaFilterOffline: null,
      offlineMangaIds: const {},
      mangaFilterLewd: null,
      mangaFilterMinRating: minRating,
      filterCategories: false,
      filterCategoriesInclude: const {},
      filterCategoriesExclude: const {},
      filterTags: false,
      filterTagsInclude: const {},
      filterTagsExclude: const {},
      sortedBy: sort,
      sortedDirection: asc,
    );

void main() {
  final items = [
    _manga(1, rating: 5),
    _manga(2, rating: 2),
    _manga(3), // unrated → 0
  ];

  test('sort by rating ascending puts unrated first, highest last', () {
    expect(_run(items, sort: MangaSort.rating, asc: true).map((m) => m.id),
        [3, 2, 1]);
  });

  test('sort by rating descending puts highest first', () {
    expect(_run(items, sort: MangaSort.rating, asc: false).map((m) => m.id),
        [1, 2, 3]);
  });

  test('minimum-rating filter excludes lower-rated and unrated', () {
    expect(_run(items, minRating: 3).map((m) => m.id), [1]);
    expect(_run(items, minRating: 2).map((m) => m.id), unorderedEquals([1, 2]));
  });

  test('minimum-rating 0 shows everything', () {
    expect(_run(items, minRating: 0).length, 3);
  });
}
