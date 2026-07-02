// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'offline_database.dart';
import 'offline_page_store.dart';
import 'offline_paths.dart';
import 'offline_sync.dart';

part 'offline_repository.g.dart';

/// Single entry point the rest of the app uses for offline state. Keeps the
/// drift database and path resolution behind one interface so callers never
/// depend on drift directly.
class OfflineRepository {
  const OfflineRepository({required this.db, required this.paths});

  final OfflineDatabase db;
  final OfflinePaths paths;

  /// Absolute on-disk path for a stored page, or null if not downloaded.
  Future<String?> localPagePath(int chapterId, int pageIndex) async {
    final rows = await (db.select(db.offlinePages)
          ..where((t) =>
              t.chapterId.equals(chapterId) & t.pageIndex.equals(pageIndex)))
        .get();
    if (rows.isEmpty) return null;
    return paths.absolute(rows.single.relativePath);
  }

  /// Ordered absolute page paths for a chapter that is downloaded on-device, or
  /// null when the chapter isn't fully downloaded — so the reader can serve it
  /// from disk (offline) instead of the server.
  Future<List<String>?> localChapterPages(int chapterId) async {
    final ch = await (db.select(db.offlineChapters)
          ..where((t) => t.id.equals(chapterId)))
        .getSingleOrNull();
    if (ch == null || ch.deviceState != OfflineDeviceState.downloaded) {
      return null;
    }
    final rows = await (db.select(db.offlinePages)
          ..where((t) => t.chapterId.equals(chapterId))
          ..orderBy([(t) => OrderingTerm(expression: t.pageIndex)]))
        .get();
    if (rows.isEmpty) return null;
    return [for (final r in rows) paths.absolute(r.relativePath)];
  }

  /// The catalog row for a manga — used when the server is unreachable so the
  /// library screen can fall back to on-device data.
  Future<OfflineManga?> mangaById(int mangaId) => db.mangaById(mangaId);

  /// The catalog row for a chapter (needed to enqueue a device download), or
  /// null if it hasn't been synced from an online read yet.
  Future<OfflineChapter?> chapterById(int chapterId) =>
      (db.select(db.offlineChapters)..where((t) => t.id.equals(chapterId)))
          .getSingleOrNull();

  /// How many of [chapterIds] currently have a device copy — for the bulk
  /// delete confirm.
  Future<int> deviceDownloadedCount(List<int> chapterIds) async {
    if (chapterIds.isEmpty) return 0;
    final rows = await (db.select(db.offlineChapters)
          ..where((t) =>
              t.id.isIn(chapterIds) &
              t.deviceState.equalsValue(OfflineDeviceState.downloaded)))
        .get();
    return rows.length;
  }

  /// Live device-download state for a chapter, so the UI reflects progress.
  Stream<OfflineDeviceState> watchChapterState(int chapterId) =>
      (db.select(db.offlineChapters)..where((t) => t.id.equals(chapterId)))
          .watchSingleOrNull()
          .map((c) => c?.deviceState ?? OfflineDeviceState.none)
          // drift re-fires every per-chapter stream on ANY chapters-table write;
          // distinct() stops a row from rebuilding unless ITS state changed
          // (avoids a 98-row rebuild storm while a series downloads).
          .distinct();

  /// Live count of pages already on disk for a chapter — drives the per-chapter
  /// download progress arc. distinct() so a row only
  /// rebuilds when its page count actually advances.
  Stream<int> watchChapterDownloadedPages(int chapterId) {
    final cnt = db.offlinePages.pageIndex.count();
    return (db.selectOnly(db.offlinePages)
          ..addColumns([cnt])
          ..where(db.offlinePages.chapterId.equals(chapterId)))
        .watchSingle()
        .map((r) => r.read(cnt) ?? 0)
        .distinct();
  }

  /// The per-series keep-offline rule (defaults to off if the manga isn't
  /// synced yet).
  Future<OfflineKeepRule> keepRuleFor(int mangaId) async {
    final m = await (db.select(db.offlineMangas)..where((t) => t.id.equals(mangaId)))
        .getSingleOrNull();
    return m?.keepRule ?? OfflineKeepRule.off;
  }

  /// The per-series keep-offline rule AND its unread-buffer size — so the UI can
  /// tick the exact "Keep next N unread" preset that's active.
  Future<({OfflineKeepRule rule, int count})> keepConfigFor(int mangaId) async {
    final m = await (db.select(db.offlineMangas)..where((t) => t.id.equals(mangaId)))
        .getSingleOrNull();
    return (rule: m?.keepRule ?? OfflineKeepRule.off, count: m?.keepUnreadCount ?? 5);
  }

  /// Manga ids with at least one chapter downloaded to this device — for the
  /// "On device" library filter.
  Future<Set<int>> deviceDownloadedMangaIds() => db.mangaIdsWithDeviceDownloads();

  /// Total bytes used by all downloaded chapters — for the storage settings UI.
  Future<int> totalDownloadedBytes() => db.totalDownloadedBytes();
}

// These are overridden at app startup (like hiveStoreProvider) with the
// runtime database + base dir resolved via path_provider on native platforms.
// They are NOT read on web (offline is disabled there), so the throwing default
// is never hit in that configuration.
@riverpod
OfflineDatabase offlineDatabase(Ref ref) => throw UnimplementedError(
    'offlineDatabaseProvider must be overridden at startup');

@riverpod
OfflinePaths offlinePaths(Ref ref) => throw UnimplementedError(
    'offlinePathsProvider must be overridden at startup');

@riverpod
OfflinePageStore offlinePageStore(Ref ref) => throw UnimplementedError(
    'offlinePageStoreProvider must be overridden at startup');

@riverpod
OfflineRepository offlineRepository(Ref ref) => OfflineRepository(
      db: ref.watch(offlineDatabaseProvider),
      paths: ref.watch(offlinePathsProvider),
    );

/// Whether on-device offline storage is available. Defaults to false and is
/// overridden to true at startup when the catalog opened (native platforms).
/// Lets callers no-op cleanly on web / when init failed.
@riverpod
bool offlineEnabled(Ref ref) => false;

/// The metadata down-sync, or null when offline storage is unavailable — so
/// online controllers can call `ref.read(offlineSyncProvider)?.syncManga(m)`
/// without caring about platform.
@riverpod
OfflineSync? offlineSync(Ref ref) {
  if (!ref.watch(offlineEnabledProvider)) return null;
  return OfflineSync(ref.watch(offlineDatabaseProvider));
}
