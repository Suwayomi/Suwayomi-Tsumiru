// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../utils/logger/logger.dart';
import '../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../../global_providers/global_providers.dart';
import 'offline_database.dart';
import 'offline_page_store.dart';
import 'offline_paths.dart';
import 'offline_server_identity.dart';
import 'offline_server_identity_repository.dart';
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
  Stream<OfflineDeviceState> watchChapterState(int chapterId) => (db
          .select(db.offlineChapters)
        ..where((t) => t.id.equals(chapterId)))
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
    final m = await (db.select(db.offlineMangas)
          ..where((t) => t.id.equals(mangaId)))
        .getSingleOrNull();
    return m?.keepRule ?? OfflineKeepRule.off;
  }

  /// The per-series keep-offline rule AND its unread-buffer size — so the UI can
  /// tick the exact "Keep next N unread" preset that's active.
  Future<({OfflineKeepRule rule, int count})> keepConfigFor(int mangaId) async {
    final m = await (db.select(db.offlineMangas)
          ..where((t) => t.id.equals(mangaId)))
        .getSingleOrNull();
    return (
      rule: m?.keepRule ?? OfflineKeepRule.off,
      count: m?.keepUnreadCount ?? 5
    );
  }

  /// Manga ids with at least one chapter downloaded to this device — for the
  /// "On device" library filter.
  Future<Set<int>> deviceDownloadedMangaIds() =>
      db.mangaIdsWithDeviceDownloads();

  /// Live version of [deviceDownloadedMangaIds] — see
  /// [OfflineDatabase.watchMangaIdsWithDeviceDownloads].
  Stream<Set<int>> watchDeviceDownloadedMangaIds() =>
      db.watchMangaIdsWithDeviceDownloads();

  /// Total bytes used by all downloaded chapters — for the storage settings UI.
  Future<int> totalDownloadedBytes() => db.totalDownloadedBytes();
}

// These are overridden at app startup with the
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

/// Repairs a chapter that claims to be downloaded but has no page rows,
/// returning its page paths when it healed. The files are usually still on
/// disk, so rebuilding the rows costs nothing; when the manifest can't vouch
/// for them, re-queue rather than leave a chapter lying about being local.
Future<List<String>?> repairDownloadedChapterPages({
  required OfflineDatabase db,
  required OfflinePageStore store,
  required OfflinePaths paths,
  required int chapterId,
  // Kept out of this function so it stays Ref-less and testable: re-queueing
  // without starting anything leaves the chapter waiting on an unrelated
  // download trigger, which is not a self-heal.
  void Function()? onRequeued,
}) async {
  final ch = await db.chapterById(chapterId);
  if (ch == null || ch.deviceState != OfflineDeviceState.downloaded) return null;

  final committed = await store.committedPages(ch.mangaId, chapterId);
  // Short counts as badly as none: rebuilding rows from a directory that lost
  // half its files certifies a truncated chapter as complete, and the reader
  // then shows it that way forever. pageCount is 0 for rows that never learned
  // their length, which is not evidence of a short read.
  final short = ch.pageCount > 0 && committed.length < ch.pageCount;
  if (committed.isEmpty || short) {
    logger.w(
      'Offline: chapter $chapterId claims downloaded with '
      '${committed.length}/${ch.pageCount} pages on disk, re-queueing',
    );
    await db.transaction(() async {
      await (db.delete(
        db.offlinePages,
      )..where((t) => t.chapterId.equals(chapterId))).go();
      await db.setChapterDeviceState(
        chapterId,
        OfflineDeviceState.queued,
        bytes: 0,
      );
    });
    onRequeued?.call();
    return null;
  }

  logger.i(
    'Offline: rebuilt ${committed.length} page rows for chapter $chapterId',
  );
  await db.commitDownloadedChapter(
    chapterId: chapterId,
    pages: committed,
    downloadedAt: ch.downloadedAt ?? DateTime.now(),
  );
  return [for (final p in committed) paths.absolute(p.relPath)];
}

/// Whether on-device offline storage is available. Defaults to false and is
/// overridden to true at startup when the catalog opened (native platforms).
/// Lets callers no-op cleanly on web / when init failed.
@riverpod
bool offlineEnabled(Ref ref) => false;

@riverpod
bool offlineActive(Ref ref) {
  if (!ref.watch(offlineEnabledProvider)) return false;
  final stamp = ref.watch(sharedPreferencesProvider).getString(
        DBKeys.offlineCatalogServerId.name,
      );
  final current = ref.watch(serverInstanceIdProvider).value;
  if (current == null) return false;
  return isOfflineCatalogActive(
    offlineEnabled: true,
    catalogServer: stamp,
    currentServer: current,
  );
}

class OfflineServerMismatch {
  const OfflineServerMismatch({
    required this.catalogServer,
    required this.currentServer,
    required this.dismissed,
  });

  final String catalogServer;
  final String currentServer;
  final bool dismissed;
}

@riverpod
Future<OfflineServerMismatch?> offlineServerMismatch(Ref ref) async {
  if (!ref.watch(offlineEnabledProvider)) return null;
  final preferences = ref.watch(sharedPreferencesProvider);
  // Read before the await: touching ref after the async gap throws if this
  // provider was disposed mid-build.
  final catalogDb = ref.watch(offlineDatabaseProvider);
  final stamp = preferences.getString(DBKeys.offlineCatalogServerId.name);
  final current = await ref.watch(serverInstanceIdProvider.future);
  if (stamp == null || stamp == current) return null;
  if (!await catalogDb.hasCatalogData()) {
    await preferences.setString(DBKeys.offlineCatalogServerId.name, current);
    await preferences.remove(DBKeys.offlineServerMismatchDismissedList.name);
    if (ref.mounted) ref.invalidate(offlineActiveProvider);
    return null;
  }
  final key = serverMismatchKey(stamp, current);
  final dismissedKeys = preferences.getStringList(
        DBKeys.offlineServerMismatchDismissedList.name,
      ) ??
      const <String>[];
  return OfflineServerMismatch(
    catalogServer: stamp,
    currentServer: current,
    dismissed: dismissedKeys.contains(key),
  );
}

Future<void> dismissOfflineServerMismatch(
  WidgetRef ref,
  OfflineServerMismatch mismatch,
) async {
  final preferences = ref.read(sharedPreferencesProvider);
  final key = serverMismatchKey(mismatch.catalogServer, mismatch.currentServer);
  // Remember each dismissed (catalog, current) pair so switching among several
  // servers doesn't un-dismiss a banner already dismissed.
  final current = preferences.getStringList(
        DBKeys.offlineServerMismatchDismissedList.name,
      ) ??
      const <String>[];
  if (!current.contains(key)) {
    await preferences.setStringList(
      DBKeys.offlineServerMismatchDismissedList.name,
      [...current, key],
    );
  }
  ref.invalidate(offlineServerMismatchProvider);
}

@riverpod
OfflineDatabase? offlineReadDatabase(Ref ref) {
  if (!ref.watch(offlineEnabledProvider)) return null;
  final stamp = ref.watch(sharedPreferencesProvider).getString(
        DBKeys.offlineCatalogServerId.name,
      );
  if (stamp != null && !ref.watch(offlineActiveProvider)) return null;
  return ref.watch(offlineDatabaseProvider);
}

/// Whether the offline library has anything to SHOW — series with files on
/// this device. Gates the "View offline" escape hatch: offering it with
/// nothing downloaded would land on an empty screen.
@riverpod
Future<bool> offlineCatalogAvailable(Ref ref) async {
  final db = ref.watch(offlineReadDatabaseProvider);
  if (db == null) return false;
  return (await db.mangaIdsWithDeviceDownloads()).isNotEmpty;
}

/// The metadata down-sync, or null when offline storage is unavailable — so
/// online controllers can call `ref.read(offlineSyncProvider)?.syncManga(m)`
/// without caring about platform.
@riverpod
OfflineSync? offlineSync(Ref ref) {
  if (!ref.watch(offlineActiveProvider)) return null;
  final identity = ref.watch(serverInstanceIdProvider).value;
  if (identity == null) return null;
  final preferences = ref.watch(sharedPreferencesProvider);
  return OfflineSync(
    ref.watch(offlineDatabaseProvider),
    // Single-manga count refetch for settling corrections whose acks raced an
    // aggregate fetch (see OfflineSync.refetchManga). Same DI precedent as the
    // push loop reading the repository directly.
    refetchManga: (mangaId) =>
        ref.read(mangaBookRepositoryProvider).getManga(mangaId: mangaId),
    onSynced: () async {
      if (preferences.getString(DBKeys.offlineCatalogServerId.name) == null) {
        await preferences.setString(
          DBKeys.offlineCatalogServerId.name,
          identity,
        );
        // This closure is captured by OfflineSync and invoked later, from
        // syncManga — this provider can have been disposed/rebuilt by then
        // (e.g. a bulk operation triggering many syncs back to back), and
        // ref.invalidate on a disposed Ref throws. The preference write above
        // already landed, so the guard above won't re-run this block anyway;
        // there's nothing left to do if the ref is gone.
        if (ref.mounted) ref.invalidate(offlineActiveProvider);
      }
    },
  );
}
