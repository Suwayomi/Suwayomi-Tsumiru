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
}) =>
    ChapterWithMangaDto(
      chapterNumber: id.toDouble(),
      fetchedAt: '${day * 86400}',
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

    test('consecutive chapters from the same manga on the same day merge',
        () {
      final result = groupUpdatesForDisplay([
        _chapter(id: 1, mangaId: 1, day: 0),
        _chapter(id: 2, mangaId: 1, day: 0),
        _chapter(id: 3, mangaId: 1, day: 0),
      ]);

      expect(result, hasLength(1),
          reason: 'all three chapters share manga and day — one group');
      expect(result.single.tail.map((c) => c.id), unorderedEquals([1, 2]),
          reason: 'the two non-head chapters fold into the tail');
    });

    test('a different manga breaks the group', () {
      final result = groupUpdatesForDisplay([
        _chapter(id: 1, mangaId: 1, day: 0),
        _chapter(id: 2, mangaId: 2, day: 0),
        _chapter(id: 3, mangaId: 1, day: 0),
      ]);

      expect(result, hasLength(3),
          reason: 'manga 2 interrupts the run of manga 1 chapters — grouping '
              'only merges strictly consecutive rows, so manga 1 does not '
              're-merge across the interruption');
    });

    test('a different day breaks the group even for the same manga', () {
      final result = groupUpdatesForDisplay([
        _chapter(id: 1, mangaId: 1, day: 0),
        _chapter(id: 2, mangaId: 1, day: 1),
      ]);

      expect(result, hasLength(2),
          reason: 'grouping is scoped to same-manga AND same-day');
      expect(result.every((e) => e.tail.isEmpty), isTrue);
    });

    test('empty input produces no entries', () {
      expect(groupUpdatesForDisplay(const []), isEmpty);
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
      expect(result.single.head.id, 4,
          reason: 'chapter 4 is the LAST unread chapter in the group');
      expect(result.single.tail.map((c) => c.id),
          unorderedEquals([1, 2, 3, 5]));
    });

    test('group head falls back to the first chapter when all are read', () {
      final result = groupUpdatesForDisplay([
        _chapter(id: 1, mangaId: 1, isRead: true),
        _chapter(id: 2, mangaId: 1, isRead: true),
      ]);

      expect(result.single.head.id, 1,
          reason: 'no unread chapter exists — fall back to the first one');
      expect(result.single.tail.map((c) => c.id), [2]);
    });

    test('among several unread chapters, the latest one is the head', () {
      final result = groupUpdatesForDisplay([
        _chapter(id: 1, mangaId: 1, isRead: false),
        _chapter(id: 2, mangaId: 1, isRead: false),
      ]);

      expect(result.single.head.id, 2);
      expect(result.single.tail.map((c) => c.id), [1]);
    });

    test('independent groups for different manga/day pairs are all preserved',
        () {
      final result = groupUpdatesForDisplay([
        _chapter(id: 1, mangaId: 1, day: 0),
        _chapter(id: 2, mangaId: 1, day: 0),
        _chapter(id: 3, mangaId: 2, day: 0),
        _chapter(id: 4, mangaId: 1, day: 1),
      ]);

      expect(result, hasLength(3));
      expect(result[0].head.id, 2);
      expect(result[0].tail.map((c) => c.id), [1]);
      expect(result[1].head.id, 3);
      expect(result[1].tail, isEmpty);
      expect(result[2].head.id, 4);
      expect(result[2].tail, isEmpty);
    });
  });

  group('pickGroupHead', () {
    test('returns the only chapter in a single-element list', () {
      final c = _chapter(id: 1, mangaId: 1);
      expect(pickGroupHead([c]), same(c));
    });

    test('returns the last unread chapter among several', () {
      final chapters = [
        _chapter(id: 1, mangaId: 1, isRead: false),
        _chapter(id: 2, mangaId: 1, isRead: true),
        _chapter(id: 3, mangaId: 1, isRead: false),
      ];
      expect(pickGroupHead(chapters).id, 3);
    });

    test('returns the first chapter when every chapter is read', () {
      final chapters = [
        _chapter(id: 1, mangaId: 1, isRead: true),
        _chapter(id: 2, mangaId: 1, isRead: true),
      ];
      expect(pickGroupHead(chapters).id, 1);
    });
  });

  group('headFlatIndexToDisplayIndex', () {
    test('empty groups produce an empty map', () {
      expect(headFlatIndexToDisplayIndex(const []), isEmpty);
    });

    test('maps each group head to its flat index, skipping tail members', () {
      final groups = groupUpdatesForDisplay([
        _chapter(id: 1, mangaId: 1, day: 0), // group 0 head (flat 0)
        _chapter(id: 2, mangaId: 1, day: 0), // group 0 tail (flat 1)
        _chapter(id: 3, mangaId: 2, day: 0), // group 1 head (flat 2)
        _chapter(id: 4, mangaId: 1, day: 1), // group 2 head (flat 3)
        _chapter(id: 5, mangaId: 1, day: 1), // group 2 tail (flat 4)
        _chapter(id: 6, mangaId: 1, day: 1), // group 2 tail (flat 5)
      ]);
      expect(groups, hasLength(3));

      final map = headFlatIndexToDisplayIndex(groups);

      expect(map, {0: 0, 2: 1, 3: 2});
    });

    test('a single all-ungrouped run maps every flat index to itself', () {
      final groups = groupUpdatesForDisplay([
        _chapter(id: 1, mangaId: 1, day: 0),
        _chapter(id: 2, mangaId: 2, day: 1),
        _chapter(id: 3, mangaId: 3, day: 2),
      ]);

      final map = headFlatIndexToDisplayIndex(groups);

      expect(map, {0: 0, 1: 1, 2: 2});
    });
  });
}
