// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/updates/updates_grouping.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

Fragment$MangaBaseDto _manga(int id) => Fragment$MangaBaseDto(
  genre: const [],
  id: id,
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  title: 'Manga $id',
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: 'manga/$id',
  user: Fragment$MangaBaseDto$user(
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: 0,
  ),
);

/// A minimal fixture chapter. [day] is a distinct calendar day expressed as
/// whole days since epoch (converted to a fetchedAt second timestamp), so
/// tests can express "same day" / "different day" without real dates.
ChapterWithMangaDto _chapter({
  required int id,
  required int mangaId,
  int day = 0,
}) => ChapterWithMangaDto(
  chapterNumber: id.toDouble(),
  fetchedAt: '${day * 86400}',
  id: id,
  mangaId: mangaId,
  name: 'Chapter $id',
  pageCount: 10,
  sourceOrder: id,
  uploadDate: '0',
  url: 'chapter/$id',
  meta: const [],
  manga: _manga(mangaId),
  user: Fragment$ChapterWithMangaDto$user(
    isBookmarked: false,
    isDownloaded: false,
    isRead: false,
    lastPageRead: 0,
    lastReadAt: '0',
  ),
);

void main() {
  group('groupUpdatesForDisplay', () {
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
  });
}
