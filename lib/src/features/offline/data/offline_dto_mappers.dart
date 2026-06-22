// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../library/domain/category/category_model.dart';
import '../../library/domain/category/graphql/__generated__/fragment.graphql.dart';
import '../../manga_book/domain/chapter/chapter_model.dart';
import '../../manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import '../../manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import 'offline_database.dart';

/// Build a [MangaDto] from an on-device catalog row. Used only as the offline
/// fallback when the server is unreachable. Fields the catalog doesn't store
/// (counts, genre, status, url) get safe defaults; the list UI reads cover +
/// title + inLibrary, which are accurate.
MangaDto offlineMangaToDto(OfflineManga m, {int chapterCount = 0}) =>
    Fragment$MangaDto(
      id: m.id,
      title: m.title,
      thumbnailUrl: m.thumbnailUrl,
      bookmarkCount: 0,
      chapters: Fragment$MangaDto$chapters(totalCount: chapterCount),
      downloadCount: 0,
      genre: const [],
      inLibrary: true,
      inLibraryAt: '0',
      initialized: true,
      meta: const <Fragment$MangaDto$meta>[],
      sourceId: '0',
      status: Enum$MangaStatus.UNKNOWN,
      unreadCount: 0,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '',
    );

/// Build a [ChapterDto] from an on-device catalog row (offline fallback).
ChapterDto offlineChapterToDto(OfflineChapter c) => Fragment$ChapterDto(
      id: c.id,
      mangaId: c.mangaId,
      name: c.name,
      chapterNumber: c.chapterIndex.toDouble(),
      sourceOrder: c.chapterIndex,
      isRead: c.isRead,
      isBookmarked: c.isBookmarked,
      isDownloaded: c.serverIsDownloaded,
      lastPageRead: c.lastPageRead,
      pageCount: c.pageCount,
      fetchedAt: '0',
      uploadDate: '0',
      lastReadAt: '0',
      url: '',
      meta: const <Fragment$ChapterDto$meta>[],
    );

/// A synthetic "Default" category used offline, when the server's category list
/// is unreachable. Carries [mangaCount] so it survives the `mangas.totalCount >
/// 0` filter (`nonZeroCategoryList`) and the library renders one flat tab of the
/// on-device catalog.
CategoryDto offlineDefaultCategoryDto(int mangaCount) => Fragment$CategoryDto(
      defaultCategory: true,
      id: 0,
      includeInDownload: Enum$IncludeOrExclude.UNSET,
      includeInUpdate: Enum$IncludeOrExclude.UNSET,
      name: 'Default',
      order: 0,
      mangas: Fragment$CategoryDto$mangas(totalCount: mangaCount),
      meta: const <Fragment$CategoryDto$meta>[],
    );
