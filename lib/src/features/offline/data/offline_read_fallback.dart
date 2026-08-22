// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/network/graphql_errors.dart';
import '../../library/domain/category/category_model.dart';
import '../../library/domain/category/graphql/__generated__/fragment.graphql.dart';
import '../../manga_book/domain/chapter/chapter_model.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import 'offline_database.dart';
import 'offline_dto_mappers.dart';

/// Fall back to the on-device cache only on a genuine loss of connectivity; a
/// server that answered with an error must surface, not be masked as offline.
bool _shouldFallBack(Object e) =>
    isConnectionError(e is OperationMessageException ? e.exception : e);

/// Bounds how long a fallback-capable read waits on the network once a
/// catalog exists to serve instead — otherwise a hung request (airplane mode,
/// a dead Cloudflare origin) burns the full client timeout before the catalog
/// appears. TimeoutException counts as a connection error, so the fallback
/// path takes over at the cap.
const kOfflineFallbackFetchTimeout = Duration(seconds: 15);

/// Runs [fetch], capped at [fetchTimeout] when [canServe] says this wrapper
/// has something to fall back to. With nothing to serve, the cap would only
/// turn a slow-but-working load into an error — so the full client timeout
/// applies.
Future<T> _boundedFetch<T>(
  Future<T> Function() fetch,
  Future<bool> Function() canServe,
  Duration fetchTimeout,
) async {
  if (!await canServe()) return fetch();
  return fetch().timeout(fetchTimeout);
}

/// Network-first read with on-device catalog fallback. Tries [fetch]; if it
/// throws and offline is available with catalog data, returns the catalog
/// mapped to the server DTO type. Otherwise rethrows the original error.
///
/// [offlineFirst] (the "View offline" button) skips the network and serves the
/// catalog straight away — still reported as unreachable so the offline banner
/// stays up.
Future<List<MangaDto>?> libraryWithOfflineFallback({
  required Future<List<MangaDto>?> Function() fetch,
  required OfflineDatabase? db,
  required bool offlineEnabled,
  void Function(bool reachable)? onReachability,
  Duration fetchTimeout = kOfflineFallbackFetchTimeout,
  bool offlineFirst = false,
  // Fired (synchronously, before return) when the result came from the
  // catalog, not the server. Callers MUST NOT sync a catalog-served result
  // back into the catalog: the DTO round-trip loses fields (lastReadAt,
  // real chapter numbers) and would overwrite good rows with the echo.
  void Function()? onCatalogServe,
}) async {
  // Null means nothing to serve, so callers rethrow the original network
  // error (or fall through to it) rather than a synthetic one.
  //
  // Scoped to series with files on this device — the offline library is for
  // reading, not browsing metadata. Everything else lives in Downloads → On
  // device.
  Future<List<MangaDto>?> serveCatalog() async {
    final downloadedIds = await db!.mangaIdsWithDeviceDownloads();
    if (downloadedIds.isEmpty) return null;
    final rows = [
      for (final m in await db.libraryManga())
        if (downloadedIds.contains(m.id)) m,
    ];
    if (rows.isEmpty) return null;
    final lastReadByManga = await db.lastReadAtByManga();
    final firstUnreadByManga = await db.firstUnreadDownloadedChapterByManga();
    final readDelta = await db.unsyncedReadDeltaByManga();
    // Load all category memberships in one query, keyed by mangaId.
    final categoryMap = await db.categoriesForMangas({
      for (final m in rows) m.id,
    });
    // The manga column carries the server's Last-Read snapshot for every
    // library entry; a chapter-row max can be newer when something was read
    // offline since the last sync. Numeric max — both are epoch strings.
    String? mergedLastRead(OfflineManga m) {
      final fromChapters = int.tryParse(lastReadByManga[m.id] ?? '');
      final fromManga = int.tryParse(m.lastReadAt ?? '');
      final best = [
        if (fromChapters != null) fromChapters,
        if (fromManga != null) fromManga,
      ];
      if (best.isEmpty) return null;
      return best.reduce((a, b) => a > b ? a : b).toString();
    }

    return [
      for (final m in rows)
        offlineMangaToDto(
          m,
          lastReadAt: mergedLastRead(m),
          firstUnread: firstUnreadByManga[m.id],
          offlineCategories: categoryMap[m.id] ?? [],
          unsyncedReadDelta: readDelta[m.id] ?? 0,
        ),
    ];
  }

  Future<bool> canServe() async =>
      db != null && (await db.mangaIdsWithDeviceDownloads()).isNotEmpty;

  if (offlineEnabled && offlineFirst && await canServe()) {
    final served = await serveCatalog();
    if (served != null) {
      onReachability?.call(false);
      onCatalogServe?.call();
      return served;
    }
  }
  try {
    final result = await _boundedFetch(fetch, canServe, fetchTimeout);
    onReachability?.call(true);
    return result;
  } catch (e) {
    // Report unreachability even when we go on to serve cache below, so the
    // outage isn't hidden from an app-wide "offline" indicator.
    final connectionLost = _shouldFallBack(e);
    onReachability?.call(!connectionLost);
    if (!offlineEnabled || !connectionLost) rethrow;
    final served = await serveCatalog();
    if (served == null) rethrow;
    onCatalogServe?.call();
    return served;
  }
}

Future<MangaDto?> mangaWithOfflineFallback({
  required Future<MangaDto?> Function() fetch,
  required OfflineDatabase? db,
  required bool offlineEnabled,
  required int mangaId,
  Duration fetchTimeout = kOfflineFallbackFetchTimeout,
  bool offlineFirst = false,
  void Function()? onCatalogServe,
}) async {
  Future<MangaDto?> serveCatalog() async {
    final m = await db!.mangaById(mangaId);
    if (m == null) return null;
    final count = (await db.chaptersForManga(mangaId)).length;
    final cats = await db.categoriesForManga(mangaId);
    final delta = (await db.unsyncedReadDeltaByManga())[mangaId] ?? 0;
    return offlineMangaToDto(
      m,
      chapterCount: count,
      offlineCategories: cats,
      unsyncedReadDelta: delta,
    );
  }

  Future<bool> canServe() async =>
      db != null && await db.mangaById(mangaId) != null;

  if (offlineEnabled && offlineFirst && db != null) {
    final served = await serveCatalog();
    if (served != null) {
      onCatalogServe?.call();
      return served;
    }
    // Not in the catalog (e.g. a browse result) — fall through to the network.
  }
  try {
    return await _boundedFetch(fetch, canServe, fetchTimeout);
  } catch (e) {
    if (!offlineEnabled || !_shouldFallBack(e)) rethrow;
    final served = await serveCatalog();
    if (served == null) rethrow;
    onCatalogServe?.call();
    return served;
  }
}

/// The reader fetches chapter metadata from the server. A downloaded chapter
/// must still open offline, so fall back to the on-device catalog row.
Future<ChapterDto?> chapterMetaWithOfflineFallback({
  required Future<ChapterDto?> Function() fetch,
  required OfflineDatabase? db,
  required bool offlineEnabled,
  required int chapterId,
  Duration fetchTimeout = kOfflineFallbackFetchTimeout,
  bool offlineFirst = false,
  void Function()? onCatalogServe,
}) async {
  Future<bool> canServe() async =>
      db != null && await db.chapterById(chapterId) != null;

  if (offlineEnabled && offlineFirst && db != null) {
    final c = await db.chapterById(chapterId);
    if (c != null) {
      onCatalogServe?.call();
      return offlineChapterToDto(c);
    }
  }
  try {
    return await _boundedFetch(fetch, canServe, fetchTimeout);
  } catch (e) {
    if (!offlineEnabled || !_shouldFallBack(e)) rethrow;
    final c = await db!.chapterById(chapterId);
    if (c == null) rethrow;
    onCatalogServe?.call();
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
  Duration fetchTimeout = kOfflineFallbackFetchTimeout,
  bool offlineFirst = false,
  void Function()? onCatalogServe,
}) async {
  Future<List<CategoryDto>?> serveCatalog() async {
    final downloadedIds = await db!.mangaIdsWithDeviceDownloads();
    final downloadedInLibrary = (await db.libraryManga())
        .where((m) => downloadedIds.contains(m.id))
        .map((m) => m.id)
        .toSet();
    if (downloadedInLibrary.isEmpty) return null;
    final storedCats = await db.allOfflineCategories();
    if (storedCats.isEmpty) {
      return [offlineDefaultCategoryDto(downloadedInLibrary.length)];
    }
    // Real per-tab counts. Every mirrored category is kept even at zero:
    // offline, empty means "nothing downloaded from it", not "you put nothing
    // in it", and dropping them left a user whose downloads all sit in one
    // category with no tab bar at all — their categories looked deleted.
    // Manga with no membership rows live in the server's default category,
    // which their DTOs don't list.
    final counts = await db.mangaCountByCategory(downloadedInLibrary);
    final uncategorized = await db.uncategorizedOf(downloadedInLibrary);
    int countFor(OfflineCategory cat) =>
        (counts[cat.id] ?? 0) + (cat.id == 0 ? uncategorized.length : 0);
    final tabs = [
      for (final cat in storedCats)
        Fragment$CategoryDto(
          defaultCategory: cat.id == 0,
          id: cat.id,
          includeInDownload: Enum$IncludeOrExclude.UNSET,
          includeInUpdate: Enum$IncludeOrExclude.UNSET,
          name: cat.name,
          order: cat.sortOrder,
          mangas: Fragment$CategoryDto$mangas(totalCount: countFor(cat)),
          // Mirrored so hidden tabs stay hidden offline.
          meta: [
            if (cat.isHidden)
              Fragment$CategoryDto$meta(
                key: kCategoryHiddenMetaKey,
                value: 'true',
              ),
          ],
        ),
    ];
    // Downloads with no home tab (uncategorizedOf already covers orphaned
    // memberships) get a synthetic Default.
    final defaultCovered = tabs.any((t) => t.id == 0);
    if (!defaultCovered && uncategorized.isNotEmpty) {
      tabs.insert(0, offlineDefaultCategoryDto(uncategorized.length));
    }
    if (tabs.isEmpty) {
      return [offlineDefaultCategoryDto(downloadedInLibrary.length)];
    }
    return tabs;
  }

  Future<bool> canServe() async =>
      db != null && (await db.mangaIdsWithDeviceDownloads()).isNotEmpty;

  if (offlineEnabled && offlineFirst && db != null) {
    final served = await serveCatalog();
    if (served != null) {
      onCatalogServe?.call();
      return served;
    }
  }
  try {
    return await _boundedFetch(fetch, canServe, fetchTimeout);
  } catch (e) {
    if (!offlineEnabled || !_shouldFallBack(e)) rethrow;
    final served = await serveCatalog();
    if (served == null) rethrow;
    onCatalogServe?.call();
    return served;
  }
}

Future<List<ChapterDto>?> chaptersWithOfflineFallback({
  required Future<List<ChapterDto>?> Function() fetch,
  required OfflineDatabase? db,
  required bool offlineEnabled,
  required int mangaId,
  Duration fetchTimeout = kOfflineFallbackFetchTimeout,
  bool offlineFirst = false,
  void Function()? onCatalogServe,
}) async {
  Future<bool> canServe() async =>
      db != null && (await db.chaptersForManga(mangaId)).isNotEmpty;

  if (offlineEnabled && offlineFirst && db != null) {
    final rows = await db.chaptersForManga(mangaId);
    if (rows.isNotEmpty) {
      onCatalogServe?.call();
      return [for (final c in rows) offlineChapterToDto(c)];
    }
  }
  try {
    return await _boundedFetch(fetch, canServe, fetchTimeout);
  } catch (e) {
    if (!offlineEnabled || !_shouldFallBack(e)) rethrow;
    final rows = await db!.chaptersForManga(mangaId);
    if (rows.isEmpty) rethrow;
    onCatalogServe?.call();
    return [for (final c in rows) offlineChapterToDto(c)];
  }
}
