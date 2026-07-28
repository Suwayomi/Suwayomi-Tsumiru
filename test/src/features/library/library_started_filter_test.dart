// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

MangaDto _manga(int id, {required bool started}) => Fragment$MangaDto(
      id: id,
      title: 'M$id',
      bookmarkCount: 0,
      chapters: Fragment$MangaDto$chapters(totalCount: 5),
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
      unreadCount: 5,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/$id',
      lastReadChapter: Fragment$ChapterDto(
        id: id * 100,
        chapterNumber: 1,
        fetchedAt: '0',
        isBookmarked: false,
        isDownloaded: false,
        isRead: started,
        lastPageRead: 0,
        lastReadAt: started ? '1700000000' : '0',
        mangaId: id,
        name: 'Chapter 1',
        pageCount: 10,
        realUrl: null,
        scanlator: null,
        sourceOrder: 1,
        uploadDate: '0',
        url: '/c/$id',
        meta: const [],
      ),
    );

List<MangaDto> _run(List<MangaDto> input, {required bool? started}) =>
    applyLibraryFilterSort(
      input,
      query: null,
      mangaFilterUnread: null,
      mangaFilterDownloaded: null,
      mangaFilterCompleted: null,
      mangaFilterStarted: started,
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
      sortedBy: MangaSort.alphabetical,
      sortedDirection: true,
    );

void main() {
  final items = [
    _manga(1, started: true),
    _manga(2, started: false),
    _manga(3, started: true),
  ];

  test('Started keeps only the ones with reading progress', () {
    expect(_run(items, started: true).map((m) => m.id), [1, 3]);
  });

  test('Not started keeps only the untouched ones', () {
    expect(_run(items, started: false).map((m) => m.id), [2]);
  });

  test('unset keeps everything', () {
    expect(_run(items, started: null).map((m) => m.id), [1, 2, 3]);
  });
}
