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

const _totalChapters = 5;

/// [readChapters] drives the server's unread count; [lastPageRead] is progress
/// inside the chapter currently being read, which is not the same thing.
MangaDto _manga(int id, {required int readChapters, int lastPageRead = 0}) =>
    Fragment$MangaDto(
      id: id,
      title: 'M$id',
      bookmarkCount: 0,
      chapters: Fragment$MangaDto$chapters(totalCount: _totalChapters),
      downloadCount: 0,
      genre: const [],
      inLibrary: true,
      inLibraryAt: '0',
      initialized: true,
      meta: const [],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords: Fragment$MangaDto$trackRecords(
        totalCount: 0,
        nodes: const [],
      ),
      unreadCount: _totalChapters - readChapters,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/$id',
      lastReadChapter: Fragment$ChapterDto(
        id: id * 100,
        chapterNumber: 1,
        fetchedAt: '0',
        isBookmarked: false,
        isDownloaded: false,
        isRead: readChapters > 0,
        lastPageRead: lastPageRead,
        lastReadAt: (readChapters > 0 || lastPageRead > 0) ? '1700000000' : '0',
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
    _manga(1, readChapters: 2),
    _manga(2, readChapters: 0),
    _manga(3, readChapters: 5),
  ];

  test('Started keeps only the ones with a finished chapter', () {
    expect(_run(items, started: true).map((m) => m.id), [1, 3]);
  });

  test('Not started keeps the rest', () {
    expect(_run(items, started: false).map((m) => m.id), [2]);
  });

  test('unset keeps everything', () {
    expect(_run(items, started: null).map((m) => m.id), [1, 2, 3]);
  });

  // Started counts finished chapters, not pages. Reading part way into a
  // chapter and stopping leaves the series unstarted, matching the server's
  // WebUI (#301).
  test('page progress in an unread chapter is not Started', () {
    final partial = [_manga(4, readChapters: 0, lastPageRead: 7)];
    expect(_run(partial, started: true), isEmpty);
    expect(_run(partial, started: false).map((m) => m.id), [4]);
  });
}
