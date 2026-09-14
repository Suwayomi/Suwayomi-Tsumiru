// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/updates/updates_screen.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

Fragment$MangaBaseDto _manga() => Fragment$MangaBaseDto(
      id: 1,
      genre: const [],
      inLibrary: true,
      inLibraryAt: '0',
      initialized: true,
      meta: const [],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      thumbnailUrl: '/thumb/1',
      title: 'Series',
      unreadCount: 0,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/1',
    );

Fragment$ChapterWithMangaDto _chapter(int id) => Fragment$ChapterWithMangaDto(
      id: id,
      chapterNumber: id.toDouble(),
      fetchedAt: '0',
      isBookmarked: false,
      isDownloaded: false,
      isRead: false,
      lastPageRead: 0,
      lastReadAt: '0',
      mangaId: 1,
      name: 'Chapter $id',
      pageCount: 10,
      sourceOrder: id,
      uploadDate: '0',
      url: '/c/$id',
      meta: const [],
      manga: _manga(),
    );

void main() {
  group('extractNewUpdatesFromPage', () {
    test('boundary in the middle — returns items before it, boundaryFound=true',
        () {
      final nodes = [_chapter(5), _chapter(4), _chapter(3), _chapter(2)];
      final existing = {2, 1};

      final result = extractNewUpdatesFromPage(nodes, existing);

      expect(result.boundaryFound, isTrue);
      expect(result.items.map((c) => c.id), [5, 4, 3]);
    });

    test('boundary at index 0 — returns empty list, boundaryFound=true', () {
      final nodes = [_chapter(3), _chapter(2), _chapter(1)];
      final existing = {3, 2, 1};

      final result = extractNewUpdatesFromPage(nodes, existing);

      expect(result.boundaryFound, isTrue);
      expect(result.items, isEmpty);
    });

    test('boundary at last index — returns all but last, boundaryFound=true',
        () {
      final nodes = [_chapter(5), _chapter(4), _chapter(3)];
      final existing = {3};

      final result = extractNewUpdatesFromPage(nodes, existing);

      expect(result.boundaryFound, isTrue);
      expect(result.items.map((c) => c.id), [5, 4]);
    });

    test('no boundary — returns all items, boundaryFound=false', () {
      final nodes = [_chapter(5), _chapter(4), _chapter(3)];
      final existing = {2, 1};

      final result = extractNewUpdatesFromPage(nodes, existing);

      expect(result.boundaryFound, isFalse);
      expect(result.items.map((c) => c.id), [5, 4, 3]);
    });

    test('empty page — returns empty list, boundaryFound=false', () {
      final result = extractNewUpdatesFromPage([], {1, 2});

      expect(result.boundaryFound, isFalse);
      expect(result.items, isEmpty);
    });

    test('empty existing set — returns all items, boundaryFound=false', () {
      final nodes = [_chapter(3), _chapter(2), _chapter(1)];

      final result = extractNewUpdatesFromPage(nodes, {});

      expect(result.boundaryFound, isFalse);
      expect(result.items.map((c) => c.id), [3, 2, 1]);
    });
  });
}
