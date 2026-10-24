// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../library/domain/category/category_model.dart';
import '../../library/domain/category/graphql/__generated__/fragment.graphql.dart';
import '../../manga_book/domain/chapter/chapter_model.dart';
import '../../manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import '../../manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import 'offline_database.dart';


List<String> offlineGenre(String? stored) {
  if (stored == null || stored.isEmpty) return const [];
  try {
    final decoded = jsonDecode(stored);
    if (decoded is! List) return const [];
    return decoded.whereType<String>().toList(growable: false);
  } on FormatException {
    return const [];
  }
}

MangaDto offlineMangaToDto(
  OfflineManga m, {
  int chapterCount = 0,
  String? lastReadAt,
  OfflineChapter? firstUnread,
  List<OfflineCategory> offlineCategories = const [],
  int unsyncedReadDelta = 0,
}) {
  // Legacy zero totals fall back to mirrored chapters so unread counts are not clamped to zero.
  final effectiveTotal = m.totalChapters > 0 ? m.totalChapters : chapterCount;

  final Fragment$MangaDto$source? source = m.sourceId == null
      ? null
      : Fragment$MangaDto$source(
          id: m.sourceId!,
          name: m.sourceName ?? '',
          lang: m.sourceLang ?? '',
          // Missing ratings use MIXED so genre tags can still filter legacy rows.
          contentWarning: m.sourceContentWarning == null
              ? Enum$ContentWarning.MIXED
              : fromJson$Enum$ContentWarning(m.sourceContentWarning!),
          displayName: m.sourceName ?? '',
          iconUrl: '',
          $extension: Fragment$MangaDto$source$extension(isObsolete: false),
        );

  final status = m.status == null
      ? Enum$MangaStatus.UNKNOWN
      : fromJson$Enum$MangaStatus(m.status!);

  final latestFetched = m.latestFetchedAt == null
      ? null
      : Fragment$MangaDto$latestFetchedChapter(
          id: 0,
          fetchedAt: m.latestFetchedAt!,
        );

  final latestUploaded = m.latestUploadedAt == null
      ? null
      : Fragment$MangaDto$latestUploadedChapter(
          id: 0,
          uploadDate: m.latestUploadedAt!,
        );

  final categoryNodes = [
    for (final cat in offlineCategories)
      Fragment$MangaDto$categories$nodes(id: cat.id),
  ];

  return Fragment$MangaDto(
    id: m.id,
    title: m.title,
    thumbnailUrl: m.thumbnailUrl,
    user: Fragment$MangaDto$user(
      bookmarkCount: m.bookmarkCount,
      downloadCount: m.downloadCount,
      firstUnreadChapter: firstUnread == null
          ? null
          : Fragment$MangaDto$user$firstUnreadChapter(id: firstUnread.id),
      inLibrary: true,
      inLibraryAt: m.inLibraryAt ?? '0',
      lastReadChapter: lastReadAt == null
          ? null
          : Fragment$MangaDto$user$lastReadChapter(
              id: 0,
              user: Fragment$MangaDto$user$lastReadChapter$user(
                isRead: true,
                lastPageRead: 0,
                lastReadAt: lastReadAt,
              ),
            ),
      // Correct stored server counts by local changes against each chapter baseline, even for partial mirrors.
      unreadCount: (m.unreadCount - unsyncedReadDelta).clamp(0, effectiveTotal),
    ),
    chapters: Fragment$MangaDto$chapters(totalCount: effectiveTotal),
    genre: offlineGenre(m.genre),
    initialized: true,
    latestFetchedChapter: latestFetched,
    latestUploadedChapter: latestUploaded,
    meta: [
      for (final e in _decodeMeta(m.metaJson).entries)
        Fragment$MangaDto$meta(key: e.key, value: e.value),
    ],
    source: source,
    sourceId: m.sourceId ?? '0',
    status: status,
    categories: Fragment$MangaDto$categories(nodes: categoryNodes),
    trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
    updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
    url: '',
  );
}

Map<String, String> _decodeMeta(String? metaJson) {
  if (metaJson == null || metaJson.isEmpty) return const {};
  try {
    return Map<String, String>.from(jsonDecode(metaJson) as Map);
  } catch (_) {
    return const {};
  }
}

ChapterDto offlineChapterToDto(OfflineChapter c) => Fragment$ChapterDto(
  id: c.id,
  mangaId: c.mangaId,
  name: c.name,
  chapterNumber: c.chapterNumber ?? c.chapterIndex.toDouble(),
  sourceOrder: c.chapterIndex,
  user: Fragment$ChapterDto$user(
    isRead: c.isRead,
    isBookmarked: c.isBookmarked,
    isDownloaded: c.serverIsDownloaded,
    lastPageRead: c.lastPageRead,
    lastReadAt: '0',
  ),
  pageCount: c.pageCount,
  fetchedAt: c.fetchedAt ?? '0',
  uploadDate: c.uploadDate ?? '0',
  url: '',
  scanlator: c.scanlator,
  meta: const <Fragment$ChapterDto$meta>[],
);

// A positive mangaCount keeps the synthetic category through nonZeroCategoryList filtering.
CategoryDto offlineDefaultCategoryDto(int mangaCount, {int categoryId = 0}) =>
    Fragment$CategoryDto(
      defaultCategory: false,
      id: categoryId,
      includeInDownload: Enum$IncludeOrExclude.UNSET,
      includeInUpdate: Enum$IncludeOrExclude.UNSET,
      name: 'Default',
      order: 0,
      mangas: Fragment$CategoryDto$mangas(totalCount: mangaCount),
      meta: const <Fragment$CategoryDto$meta>[],
    );
