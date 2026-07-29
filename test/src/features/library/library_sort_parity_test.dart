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

MangaDto _manga(
  int id, {
  required String title,
  int unreadCount = 0,
  int totalChapters = 5,
}) =>
    Fragment$MangaDto(
      id: id,
      title: title,
      bookmarkCount: 0,
      chapters: Fragment$MangaDto$chapters(totalCount: totalChapters),
      downloadCount: 0,
      genre: const [],
      inLibrary: true,
      inLibraryAt: '0',
      initialized: true,
      meta: const [],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords:
          Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
      unreadCount: unreadCount,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/$id',
    );

List<int> _sorted(
  List<MangaDto> input, {
  required MangaSort by,
  required bool ascending,
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
      mangaFilterMinRating: 0,
      filterCategories: false,
      filterCategoriesInclude: const {},
      filterCategoriesExclude: const {},
      filterTags: false,
      filterTagsInclude: const {},
      filterTagsExclude: const {},
      sortedBy: by,
      sortedDirection: ascending,
    ).map((m) => m.id).toList();

void main() {
  group('alphabetical sort folds case and accents', () {
    // Komikku lowercases both titles then compares with a PRIMARY-strength
    // collator (LibraryScreenModel.kt:635-639, SortUtil.kt:6-15). Raw
    // compareTo is UTF-16 code-unit order, which puts every capitalised
    // title before every lowercase one.
    final items = [
      _manga(1, title: 'Zebra'),
      _manga(2, title: 'apple'),
      _manga(3, title: 'Éclair'),
    ];

    test('ascending orders by base letter, not by code unit', () {
      expect(_sorted(items, by: MangaSort.alphabetical, ascending: true),
          [2, 3, 1]);
    });

    test('descending is the exact reverse', () {
      expect(_sorted(items, by: MangaSort.alphabetical, ascending: false),
          [1, 3, 2]);
    });
  });

  group('unread sort pins zero-unread last in both directions', () {
    // "Ensure unread content comes first" — LibraryScreenModel.kt:669-675.
    // The zero branches are direction-aware there and the comparator is
    // reversed separately, so zero-unread is last whichever way you sort.
    final items = [
      _manga(1, title: 'A', unreadCount: 0),
      _manga(2, title: 'B', unreadCount: 5),
      _manga(3, title: 'C', unreadCount: 3),
    ];

    test('ascending puts fewest-unread first but zero last', () {
      expect(_sorted(items, by: MangaSort.unread, ascending: true), [3, 2, 1]);
    });

    test('descending puts most-unread first and still zero last', () {
      expect(_sorted(items, by: MangaSort.unread, ascending: false), [2, 3, 1]);
    });
  });

  group('ties break alphabetically, not by id', () {
    // thenComparator(sortAlphabetically) — LibraryScreenModel.kt:724, applied
    // after the direction reversal so the tie-break is never inverted.
    final items = [
      _manga(1, title: 'Zebra', totalChapters: 5),
      _manga(2, title: 'Apple', totalChapters: 5),
    ];

    test('equal keys fall back to title', () {
      expect(_sorted(items, by: MangaSort.totalChapters, ascending: true),
          [2, 1]);
    });

    test('tie-break is not inverted by descending', () {
      expect(_sorted(items, by: MangaSort.totalChapters, ascending: false),
          [2, 1]);
    });
  });
}
