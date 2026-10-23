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
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  thumbnailUrl: '/thumb/1',
  title: 'Series',
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/1',
  user: Fragment$MangaBaseDto$user(
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: 0,
  ),
);

Fragment$ChapterWithMangaDto _chapter(int id) => Fragment$ChapterWithMangaDto(
  id: id,
  chapterNumber: id.toDouble(),
  fetchedAt: '0',
  mangaId: 1,
  name: 'Chapter $id',
  pageCount: 10,
  sourceOrder: id,
  uploadDate: '0',
  url: '/c/$id',
  meta: const [],
  manga: _manga(),
  user: Fragment$ChapterWithMangaDto$user(
    isBookmarked: false,
    isDownloaded: false,
    isRead: false,
    lastPageRead: 0,
    lastReadAt: '0',
  ),
);

void main() {
  group('extractNewUpdatesFromPage', () {
    test(
      'boundary in the middle — returns items before it, boundaryFound=true',
      () {
        final nodes = [_chapter(5), _chapter(4), _chapter(3), _chapter(2)];
        final existing = {2, 1};

        final result = extractNewUpdatesFromPage(nodes, existing);

        expect(result.boundaryFound, isTrue);
        expect(result.items.map((c) => c.id), [5, 4, 3]);
      },
    );
  });
}
