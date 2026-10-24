// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/crash/diagnostics.dart';
import '../../../utils/crash/redact_tokens.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/network/graphql_errors.dart';
import '../../library/domain/category/category_model.dart';
import '../../library/domain/category/graphql/__generated__/fragment.graphql.dart';
import '../../manga_book/domain/chapter/chapter_model.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import 'offline_database.dart';
import 'offline_dto_mappers.dart';

// Fall back only on connectivity loss; server errors must still surface.

bool _shouldFallBack(Object e) =>
    isConnectionError(e is OperationMessageException ? e.exception : e);

// Bound network waits only when a catalog can serve the fallback.
const kOfflineFallbackFetchTimeout = Duration(seconds: 15);

Future<T> _boundedFetch<T>(
  Future<T> Function() fetch,
  Future<bool> Function() canServe,
  Duration fetchTimeout,
) async {
  if (!await canServe()) return fetch();
  return fetch().timeout(fetchTimeout);
}

void _refreshInBackground<T extends Object>({
  required Future<T?> Function() fetch,
  required void Function(T value) onAnswer,
}) {
  unawaited(() async {
    try {
      final value = await fetch();
      if (value != null) onAnswer(value);
    } catch (_) {
    }
  }());
}

/// Requires downloaded state and page rows, matching localChapterPages.
Future<bool> chapterCompleteOnDevice(OfflineDatabase db, int chapterId) async {
  final c = await db.chapterById(chapterId);
  if (c == null || c.deviceState != OfflineDeviceState.downloaded) {
    return false;
  }
  return (await db.downloadedPageCount(chapterId)) > 0;
}

/// Falls back on connectivity loss; [offlineFirst] skips network and keeps the offline banner.
Future<List<MangaDto>?> libraryWithOfflineFallback({
  required Future<List<MangaDto>?> Function() fetch,
  required OfflineDatabase? db,
  required bool offlineEnabled,
  void Function(bool reachable)? onReachability,
  Duration fetchTimeout = kOfflineFallbackFetchTimeout,
  bool offlineFirst = false,
  // Catalog DTOs lose fields on round-trip; callers must not sync them back into storage.
  void Function()? onCatalogServe,
}) async {
  // Null means no fallback; only series with device files belong in the offline library.
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
    final chapterCounts = await db.chapterCountByManga();
    final categoryMap = await db.categoriesForMangas({
      for (final m in rows) m.id,
    });
    // Offline reads may be newer than manga snapshots; compare epoch strings numerically.
    String? mergedLastRead(OfflineManga m) {
      final fromChapters = int.tryParse(lastReadByManga[m.id] ?? '');
      final fromManga = int.tryParse(m.lastReadAt ?? '');
      final best = [?fromChapters, ?fromManga];
      if (best.isEmpty) return null;
      return best.reduce((a, b) => a > b ? a : b).toString();
    }

    return [
      for (final m in rows)
        offlineMangaToDto(
          m,
          // Unsynced totalChapters must not clamp unread count to zero.
          chapterCount: chapterCounts[m.id] ?? 0,
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
      _logLibraryCatalogServe('offline-first', served.length);
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
    final connectionLost = _shouldFallBack(e);
    onReachability?.call(!connectionLost);
    if (!offlineEnabled || !connectionLost) rethrow;
    final served = await serveCatalog();
    if (served == null) rethrow;
    _logLibraryCatalogServe(
      e is TimeoutException ? 'fetch-timeout' : 'connection-error',
      served.length,
      error: e,
    );
    onCatalogServe?.call();
    return served;
  }
}

void _logLibraryCatalogServe(String reason, int count, {Object? error}) =>
    recordDiagnostic(
      redactTokens(
        '[${DateTime.now().toIso8601String()}] library-catalog-serve: '
        'reason=$reason manga=$count'
        '${error == null ? '' : ' error=${error.runtimeType}: $error'}\n',
      ),
    );

Future<MangaDto?> mangaWithOfflineFallback({
  required Future<MangaDto?> Function() fetch,
  required OfflineDatabase? db,
  required bool offlineEnabled,
  required int mangaId,
  Duration fetchTimeout = kOfflineFallbackFetchTimeout,
  bool offlineFirst = false,
  // With onServerAnswer, a complete device copy opens immediately and refreshes in the background.
  Future<bool> Function()? deviceCopyOnDisk,
  void Function(MangaDto value)? onServerAnswer,
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

  if (offlineEnabled && db != null) {
    final inCatalog = await db.mangaById(mangaId) != null;
    final deviceFirst =
        inCatalog &&
        !offlineFirst &&
        onServerAnswer != null &&
        deviceCopyOnDisk != null &&
        await deviceCopyOnDisk();
    if (inCatalog && (offlineFirst || deviceFirst)) {
      final served = await serveCatalog();
      if (served != null) {
        onCatalogServe?.call();
        if (deviceFirst) {
          _refreshInBackground(fetch: fetch, onAnswer: onServerAnswer);
        }
        return served;
      }
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

Future<ChapterDto?> chapterMetaWithOfflineFallback({
  required Future<ChapterDto?> Function() fetch,
  required OfflineDatabase? db,
  required bool offlineEnabled,
  required int chapterId,
  Duration fetchTimeout = kOfflineFallbackFetchTimeout,
  bool offlineFirst = false,
  // With onServerAnswer, a complete device copy opens immediately and refreshes in the background.
  Future<bool> Function()? deviceCopyOnDisk,
  void Function(ChapterDto value)? onServerAnswer,
  void Function()? onCatalogServe,
}) async {
  Future<bool> canServe() async =>
      db != null && await db.chapterById(chapterId) != null;

  if (offlineEnabled && db != null) {
    final c = await db.chapterById(chapterId);
    final deviceFirst =
        !offlineFirst &&
        c != null &&
        onServerAnswer != null &&
        deviceCopyOnDisk != null &&
        await deviceCopyOnDisk();
    if (offlineFirst || deviceFirst) {
      if (c != null) {
        onCatalogServe?.call();
        if (deviceFirst) {
          _refreshInBackground(fetch: fetch, onAnswer: onServerAnswer);
        }
        return offlineChapterToDto(c);
      }
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

Future<List<CategoryDto>?> categoriesWithOfflineFallback({
  required Future<List<CategoryDto>?> Function() fetch,
  required OfflineDatabase? db,
  required bool offlineEnabled,
  Duration fetchTimeout = kOfflineFallbackFetchTimeout,
  bool offlineFirst = false,
  int? defaultCategoryId = 0,
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
      return defaultCategoryId == null
          ? null
          : [
              offlineDefaultCategoryDto(
                downloadedInLibrary.length,
                categoryId: defaultCategoryId,
              ),
            ];
    }
    // Keep empty mirrored categories: no downloads does not mean the category is absent.
    final counts = await db.mangaCountByCategory(downloadedInLibrary);
    final uncategorized = await db.uncategorizedOf(downloadedInLibrary);
    int countFor(OfflineCategory cat) =>
        (counts[cat.id] ?? 0) +
        (cat.isDefaultCategory ? uncategorized.length : 0);
    final tabs = [
      for (final cat in storedCats)
        Fragment$CategoryDto(
          defaultCategory: cat.autoAdd,
          id: cat.id,
          includeInDownload: Enum$IncludeOrExclude.UNSET,
          includeInUpdate: Enum$IncludeOrExclude.UNSET,
          name: cat.name,
          order: cat.sortOrder,
          mangas: Fragment$CategoryDto$mangas(totalCount: countFor(cat)),
          meta: [
            if (cat.isHidden)
              Fragment$CategoryDto$meta(
                key: kCategoryHiddenMetaKey,
                value: 'true',
              ),
          ],
        ),
    ];
    final defaultCovered = storedCats.any(
      (category) => category.isDefaultCategory,
    );
    if (!defaultCovered &&
        defaultCategoryId != null &&
        uncategorized.isNotEmpty) {
      tabs.insert(
        0,
        offlineDefaultCategoryDto(
          uncategorized.length,
          categoryId: defaultCategoryId,
        ),
      );
    }
    if (tabs.isEmpty) {
      return defaultCategoryId == null
          ? null
          : [
              offlineDefaultCategoryDto(
                downloadedInLibrary.length,
                categoryId: defaultCategoryId,
              ),
            ];
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
