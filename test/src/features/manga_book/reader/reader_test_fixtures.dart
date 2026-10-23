// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

MangaDto testManga() => Fragment$MangaDto(
  id: 1,
  title: 'Test Manga',
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  genre: const [],
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/1',
  user: Fragment$MangaDto$user(
    bookmarkCount: 0,
    downloadCount: 0,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: 0,
  ),
);

ChapterDto testChapter({int id = 1, String name = 'Chapter 1'}) =>
    Fragment$ChapterDto(
      chapterNumber: 1,
      fetchedAt: '0',
      id: id,
      mangaId: 1,
      name: name,
      pageCount: 3,
      sourceOrder: 1,
      uploadDate: '0',
      url: '/chapter/$id',
      meta: const [],
      user: Fragment$ChapterDto$user(
        isBookmarked: false,
        isDownloaded: false,
        isRead: false,
        lastPageRead: 0,
        lastReadAt: '0',
      ),
    );
