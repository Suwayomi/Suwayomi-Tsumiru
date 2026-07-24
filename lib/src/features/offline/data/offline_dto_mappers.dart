// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../browse_center/domain/source/graphql/__generated__/fragment.graphql.dart';
import '../../library/domain/category/category_model.dart';
import '../../library/domain/category/graphql/__generated__/fragment.graphql.dart';
import '../../manga_book/domain/chapter/chapter_model.dart';
import '../../manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import '../../manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import 'offline_database.dart';

/// Build a [MangaDto] from an on-device catalog row. Used only as the offline
/// fallback when the server is unreachable. All server-sourced metadata fields
/// (source, status, counts, timestamps, categories) are restored from the
/// catalog so filters/sort/badges/grouping all work offline.
MangaDto offlineMangaToDto(
  OfflineManga m, {
  int chapterCount = 0,
  String? lastReadAt,
  OfflineChapter? firstUnread,
  List<OfflineCategory> offlineCategories = const [],
}) {
  // Restore source from stored columns
  final Fragment$SourceDto? source = m.sourceId == null
      ? null
      : Fragment$SourceDto(
          id: m.sourceId!,
          name: m.sourceName ?? '',
          lang: m.sourceLang ?? '',
          isNsfw: m.sourceIsNsfw,
          displayName: m.sourceName ?? '',
          iconUrl: '',
          isConfigurable: false,
          supportsLatest: false,
          meta: const <Fragment$SourceDto$meta>[],
          $extension:
              Fragment$SourceDto$extension(pkgName: '', isObsolete: false),
        );

  // Restore status (stored as the enum name string)
  final status = m.status == null
      ? Enum$MangaStatus.UNKNOWN
      : fromJson$Enum$MangaStatus(m.status!);

  // Restore latestFetchedChapter (carries fetchedAt for sort; minimal stub otherwise)
  final latestFetched = m.latestFetchedAt == null
      ? null
      : Fragment$ChapterDto(
          id: 0,
          mangaId: m.id,
          name: '',
          chapterNumber: 0,
          sourceOrder: 0,
          isRead: false,
          isBookmarked: false,
          isDownloaded: false,
          lastPageRead: 0,
          pageCount: 0,
          fetchedAt: m.latestFetchedAt!,
          uploadDate: '0',
          lastReadAt: '0',
          url: '',
          meta: const <Fragment$ChapterDto$meta>[],
        );

  // Restore latestUploadedChapter (carries uploadDate for sort)
  final latestUploaded = m.latestUploadedAt == null
      ? null
      : Fragment$ChapterDto(
          id: 0,
          mangaId: m.id,
          name: '',
          chapterNumber: 0,
          sourceOrder: 0,
          isRead: false,
          isBookmarked: false,
          isDownloaded: false,
          lastPageRead: 0,
          pageCount: 0,
          fetchedAt: '0',
          uploadDate: m.latestUploadedAt!,
          lastReadAt: '0',
          url: '',
          meta: const <Fragment$ChapterDto$meta>[],
        );

  // Restore category membership
  final categoryNodes = [
    for (final cat in offlineCategories)
      Fragment$MangaDto$categories$nodes(id: cat.id),
  ];

  return Fragment$MangaDto(
    id: m.id,
    title: m.title,
    thumbnailUrl: m.thumbnailUrl,
    bookmarkCount: m.bookmarkCount,
    chapters: Fragment$MangaDto$chapters(
        totalCount: m.totalChapters > 0 ? m.totalChapters : chapterCount),
    downloadCount: m.downloadCount,
    // The next unread chapter that's downloaded on this device, if any. Drives
    // the offline "continue reading" button — left null (button hidden) when
    // the next unread chapter isn't on the device, so it's never a dead end.
    firstUnreadChapter:
        firstUnread == null ? null : offlineChapterToDto(firstUnread),
    genre: const [],
    inLibrary: true,
    inLibraryAt: m.inLibraryAt ?? '0',
    initialized: true,
    // Carries the manga's most-recent read timestamp so the offline library's
    // "Last Read" sort works; only this field is read off it (see the sort in
    // library_controller). Null when nothing in the manga has been read.
    lastReadChapter: lastReadAt == null
        ? null
        : Fragment$ChapterDto(
            id: 0,
            mangaId: m.id,
            name: '',
            chapterNumber: 0,
            sourceOrder: 0,
            isRead: true,
            isBookmarked: false,
            isDownloaded: false,
            lastPageRead: 0,
            pageCount: 0,
            fetchedAt: '0',
            uploadDate: '0',
            lastReadAt: lastReadAt,
            url: '',
            meta: const <Fragment$ChapterDto$meta>[],
          ),
    latestFetchedChapter: latestFetched,
    latestUploadedChapter: latestUploaded,
    meta: const <Fragment$MangaDto$meta>[],
    source: source,
    sourceId: m.sourceId ?? '0',
    status: status,
    categories: Fragment$MangaDto$categories(nodes: categoryNodes),
    trackRecords: Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
    unreadCount: m.unreadCount,
    updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
    url: '',
  );
}

/// Build a [ChapterDto] from an on-device catalog row (offline fallback).
ChapterDto offlineChapterToDto(OfflineChapter c) => Fragment$ChapterDto(
      id: c.id,
      mangaId: c.mangaId,
      name: c.name,
      // Real number when synced (lets dedup group duplicates offline, #141);
      // index fallback for pre-v9 rows keeps numbers unique = no collapse.
      chapterNumber: c.chapterNumber ?? c.chapterIndex.toDouble(),
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
      scanlator: c.scanlator,
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
