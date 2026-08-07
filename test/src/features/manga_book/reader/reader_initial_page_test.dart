// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/utils/reader_initial_page.dart';

ChapterDto _chapter({
  bool isRead = false,
  int lastPageRead = 0,
  int pageCount = 5,
}) =>
    Fragment$ChapterDto(
      chapterNumber: 1,
      fetchedAt: '0',
      id: 1,
      isBookmarked: false,
      isDownloaded: false,
      isRead: isRead,
      lastPageRead: lastPageRead,
      lastReadAt: '0',
      mangaId: 1,
      name: 'Chapter 1',
      pageCount: pageCount,
      sourceOrder: 1,
      uploadDate: '0',
      url: '/chapter/1',
      meta: const [],
    );

ChapterPagesDto _pages({
  int loadedCount = 5,
  int pageCount = 5,
}) =>
    ChapterPagesDto(
      chapter: ChapterPagesChapterDto(id: 1, pageCount: pageCount),
      pages: [
        for (var index = 0; index < loadedCount; index++) '/page/$index',
      ],
    );

void main() {
  group('readerInitialPageIndex', () {
    test('opens previous chapters on the last loaded page', () {
      final index = readerInitialPageIndex(
        chapter: _chapter(lastPageRead: 1),
        chapterPages: _pages(loadedCount: 5),
        openAtEnd: true,
      );

      expect(index, 4);
    });

    test('uses saved progress for normal resume', () {
      final index = readerInitialPageIndex(
        chapter: _chapter(lastPageRead: 2),
        chapterPages: _pages(loadedCount: 5),
        openAtEnd: false,
      );

      expect(index, 2);
    });

    test('starts read chapters from the first page', () {
      final index = readerInitialPageIndex(
        chapter: _chapter(isRead: true, lastPageRead: 4),
        chapterPages: _pages(loadedCount: 5),
        openAtEnd: false,
      );

      expect(index, 0);
    });

    test('clamps stale progress to the loaded pages', () {
      final index = readerInitialPageIndex(
        chapter: _chapter(lastPageRead: 99),
        chapterPages: _pages(loadedCount: 3),
        openAtEnd: false,
      );

      expect(index, 2);
    });

    test('falls back to the chapter page count before pages load', () {
      final index = readerInitialPageIndex(
        chapter: _chapter(lastPageRead: 99, pageCount: 6),
        chapterPages: _pages(loadedCount: 0, pageCount: 6),
        openAtEnd: true,
      );

      expect(index, 5);
    });
  });
}
