// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../library/domain/category/category_model.dart';
import '../../library/domain/category/graphql/__generated__/fragment.graphql.dart';
import '../../manga_book/domain/chapter/chapter_model.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import 'offline_database.dart';
import 'offline_dto_mappers.dart';

/// Network-first read with on-device catalog fallback. Tries [fetch]; if it
/// throws and offline is available with catalog data, returns the catalog
/// mapped to the server DTO type. Otherwise rethrows the original error.
Future<List<MangaDto>?> libraryWithOfflineFallback({
  required Future<List<MangaDto>?> Function() fetch,
  required OfflineDatabase? db,
  required bool offlineEnabled,
}) async {
  try {
    return await fetch();
  } catch (_) {
    if (!offlineEnabled) rethrow;
    final rows = await db!.libraryManga();
    if (rows.isEmpty) rethrow;
    final lastReadByManga = await db.lastReadAtByManga();
    final firstUnreadByManga = await db.firstUnreadDownloadedChapterByManga();
    // Load all category memberships in one pass keyed by mangaId
    final categoryMap = <int, List<OfflineCategory>>{};
    for (final m in rows) {
      categoryMap[m.id] = await db.categoriesForManga(m.id);
    }
    return [
      for (final m in rows)
        offlineMangaToDto(
          m,
          lastReadAt: lastReadByManga[m.id],
          firstUnread: firstUnreadByManga[m.id],
          offlineCategories: categoryMap[m.id] ?? [],
        ),
    ];
  }
}

Future<MangaDto?> mangaWithOfflineFallback({
  required Future<MangaDto?> Function() fetch,
  required OfflineDatabase? db,
  required bool offlineEnabled,
  required int mangaId,
}) async {
  try {
    return await fetch();
  } catch (_) {
    if (!offlineEnabled) rethrow;
    final m = await db!.mangaById(mangaId);
    if (m == null) rethrow;
    final count = (await db.chaptersForManga(mangaId)).length;
    final cats = await db.categoriesForManga(mangaId);
    return offlineMangaToDto(m, chapterCount: count, offlineCategories: cats);
  }
}

/// The reader fetches chapter metadata from the server. A downloaded chapter
/// must still open offline, so fall back to the on-device catalog row.
Future<ChapterDto?> chapterMetaWithOfflineFallback({
  required Future<ChapterDto?> Function() fetch,
  required OfflineDatabase? db,
  required bool offlineEnabled,
  required int chapterId,
}) async {
  try {
    return await fetch();
  } catch (_) {
    if (!offlineEnabled) rethrow;
    final c = await db!.chapterById(chapterId);
    if (c == null) rethrow;
    return offlineChapterToDto(c);
  }
}

/// The library screen is gated on the category list (the tabs). Offline that
/// server fetch fails before any per-category manga list runs, blanking the
/// whole screen. Fall back to a single synthetic "Default" category so the
/// library renders the on-device catalog as one flat tab.
Future<List<CategoryDto>?> categoriesWithOfflineFallback({
  required Future<List<CategoryDto>?> Function() fetch,
  required OfflineDatabase? db,
  required bool offlineEnabled,
}) async {
  try {
    return await fetch();
  } catch (_) {
    if (!offlineEnabled) rethrow;
    final count = (await db!.libraryManga()).length;
    if (count == 0) rethrow;
    final storedCats = await db.allOfflineCategories();
    if (storedCats.isNotEmpty) {
      return [
        for (final cat in storedCats)
          Fragment$CategoryDto(
            defaultCategory: cat.id == 0,
            id: cat.id,
            includeInDownload: Enum$IncludeOrExclude.UNSET,
            includeInUpdate: Enum$IncludeOrExclude.UNSET,
            name: cat.name,
            order: cat.sortOrder,
            mangas: Fragment$CategoryDto$mangas(totalCount: count),
            meta: const <Fragment$CategoryDto$meta>[],
          ),
      ];
    }
    return [offlineDefaultCategoryDto(count)];
  }
}

Future<List<ChapterDto>?> chaptersWithOfflineFallback({
  required Future<List<ChapterDto>?> Function() fetch,
  required OfflineDatabase? db,
  required bool offlineEnabled,
  required int mangaId,
}) async {
  try {
    return await fetch();
  } catch (_) {
    if (!offlineEnabled) rethrow;
    final rows = await db!.chaptersForManga(mangaId);
    if (rows.isEmpty) rethrow;
    return [for (final c in rows) offlineChapterToDto(c)];
  }
}
