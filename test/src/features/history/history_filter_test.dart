// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/history/domain/history_item.dart';
import 'package:tsumiru/src/features/history/presentation/history_controller.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

HistoryItemDto _item({
  bool isRead = false,
  int unreadCount = 3,
  bool inLibrary = true,
}) =>
    Fragment$ChapterWithMangaDto(
      id: 1,
      chapterNumber: 1,
      fetchedAt: '0',
      isBookmarked: false,
      isDownloaded: false,
      isRead: isRead,
      lastPageRead: isRead ? 10 : 4,
      lastReadAt: '1700000000',
      mangaId: 7,
      name: 'Chapter 1',
      pageCount: 10,
      sourceOrder: 1,
      uploadDate: '0',
      url: '/c/1',
      meta: const [],
      manga: Fragment$MangaBaseDto(
        id: 7,
        genre: const [],
        inLibrary: inLibrary,
        inLibraryAt: '0',
        initialized: true,
        meta: const [],
        sourceId: '1',
        status: Enum$MangaStatus.ONGOING,
        title: 'Series',
        unreadCount: unreadCount,
        updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
        url: '/manga/7',
      ),
    );

void main() {
  group('historyItemMatchesFilter', () {
    test('no filter keeps everything', () {
      expect(historyItemMatchesFilter(_item(), kNoHistoryFilter), isTrue);
      expect(
        historyItemMatchesFilter(
          _item(isRead: true, unreadCount: 0, inLibrary: false),
          kNoHistoryFilter,
        ),
        isTrue,
      );
    });

    test('unfinished series keys off remaining unread chapters', () {
      const unfinished =
          (unfinishedSeries: true, unread: null, inLibrary: null);
      expect(historyItemMatchesFilter(_item(unreadCount: 3), unfinished), isTrue);
      expect(
        historyItemMatchesFilter(_item(unreadCount: 0), unfinished),
        isFalse,
      );

      const finished = (unfinishedSeries: false, unread: null, inLibrary: null);
      expect(historyItemMatchesFilter(_item(unreadCount: 0), finished), isTrue);
      expect(historyItemMatchesFilter(_item(unreadCount: 3), finished), isFalse);
    });

    test('unread keys off the chapter itself, not the series', () {
      const unread = (unfinishedSeries: null, unread: true, inLibrary: null);
      expect(historyItemMatchesFilter(_item(isRead: false), unread), isTrue);
      expect(historyItemMatchesFilter(_item(isRead: true), unread), isFalse);

      const read = (unfinishedSeries: null, unread: false, inLibrary: null);
      expect(historyItemMatchesFilter(_item(isRead: true), read), isTrue);
      expect(historyItemMatchesFilter(_item(isRead: false), read), isFalse);
    });

    test('library membership filters both ways', () {
      const inLibrary = (unfinishedSeries: null, unread: null, inLibrary: true);
      expect(historyItemMatchesFilter(_item(inLibrary: true), inLibrary), isTrue);
      expect(
        historyItemMatchesFilter(_item(inLibrary: false), inLibrary),
        isFalse,
      );

      const notInLibrary =
          (unfinishedSeries: null, unread: null, inLibrary: false);
      expect(
        historyItemMatchesFilter(_item(inLibrary: false), notInLibrary),
        isTrue,
      );
      expect(
        historyItemMatchesFilter(_item(inLibrary: true), notInLibrary),
        isFalse,
      );
    });

    test('filters combine, so all must pass', () {
      const filter = (unfinishedSeries: true, unread: true, inLibrary: true);
      expect(historyItemMatchesFilter(_item(), filter), isTrue);
      // Fails on library membership alone.
      expect(
        historyItemMatchesFilter(_item(inLibrary: false), filter),
        isFalse,
      );
    });
  });
}
