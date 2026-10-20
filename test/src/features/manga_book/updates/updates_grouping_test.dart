// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/updates/updates_grouping.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

Fragment$MangaBaseDto _manga(int id) => Fragment$MangaBaseDto(
  genre: const [],
  id: id,
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  title: 'Manga $id',
  unreadCount: 0,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: 'manga/$id',
);

/// A minimal fixture chapter. [day] is a distinct calendar day expressed as
/// whole days since epoch (converted to a fetchedAt second timestamp), so
/// tests can express "same day" / "different day" without real dates.
ChapterWithMangaDto _chapter({
  required int id,
  required int mangaId,
  int day = 0,
  bool isRead = false,
  String? fetchedAt,
}) => ChapterWithMangaDto(
  chapterNumber: id.toDouble(),
  fetchedAt: fetchedAt ?? '${day * 86400}',
  id: id,
  isBookmarked: false,
  isDownloaded: false,
  isRead: isRead,
  lastPageRead: 0,
  lastReadAt: '0',
  mangaId: mangaId,
  name: 'Chapter $id',
  pageCount: 10,
  sourceOrder: id,
  uploadDate: '0',
  url: 'chapter/$id',
  meta: const [],
  manga: _manga(mangaId),
);

void main() {
  group('groupUpdatesForDisplay', () {
    test('a single chapter becomes an ungrouped entry', () {
      final result = groupUpdatesForDisplay([_chapter(id: 1, mangaId: 1)]);

      expect(result, hasLength(1));
      expect(result.single.head.id, 1);
      expect(result.single.tail, isEmpty);
    });

    test('consecutive chapters from the same manga on the same day merge', () {
      final result = groupUpdatesForDisplay([
        _chapter(id: 1, mangaId: 1, day: 0),
        _chapter(id: 2, mangaId: 1, day: 0),
        _chapter(id: 3, mangaId: 1, day: 0),
      ]);

      expect(
        result,
        hasLength(1),
        reason: 'all three chapters share manga and day — one group',
      );
      expect(
        result.single.tail.map((c) => c.id),
        unorderedEquals([1, 2]),
        reason: 'the two non-head chapters fold into the tail',
      );
    });

    test('a different manga breaks the group', () {
      final result = groupUpdatesForDisplay([
        _chapter(id: 1, mangaId: 1, day: 0),
        _chapter(id: 2, mangaId: 2, day: 0),
        _chapter(id: 3, mangaId: 1, day: 0),
      ]);

      expect(
        result,
        hasLength(3),
        reason:
            'manga 2 interrupts the run of manga 1 chapters — grouping '
            'only merges strictly consecutive rows, so manga 1 does not '
            're-merge across the interruption',
      );
    });

    test('a different day breaks the group even for the same manga', () {
      final result = groupUpdatesForDisplay([
        _chapter(id: 1, mangaId: 1, day: 0),
        _chapter(id: 2, mangaId: 1, day: 1),
      ]);

      expect(
        result,
        hasLength(2),
        reason: 'grouping is scoped to same-manga AND same-day',
      );
      expect(result.every((e) => e.tail.isEmpty), isTrue);
    });

    test('group head is the last unread chapter', () {
      final result = groupUpdatesForDisplay([
        _chapter(id: 1, mangaId: 1, isRead: true),
        _chapter(id: 2, mangaId: 1, isRead: false),
        _chapter(id: 3, mangaId: 1, isRead: true),
        _chapter(id: 4, mangaId: 1, isRead: false),
        _chapter(id: 5, mangaId: 1, isRead: true),
      ]);

      expect(result, hasLength(1));
      expect(
        result.single.head.id,
        4,
        reason: 'chapter 4 is the LAST unread chapter in the group',
      );
      expect(
        result.single.tail.map((c) => c.id),
        unorderedEquals([1, 2, 3, 5]),
      );
    });
  });

  group('dateHeaderIndices', () {
    test('a single day produces exactly one header, at index 0', () {
      final items = [
        _chapter(id: 1, mangaId: 1, day: 0),
        _chapter(id: 2, mangaId: 1, day: 0),
        _chapter(id: 3, mangaId: 2, day: 0),
      ];

      expect(dateHeaderIndices(items), {0});
    });
  });
}
