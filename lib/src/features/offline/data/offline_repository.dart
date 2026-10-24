// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/logger/logger.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../manga_book/data/manga_book/manga_book_repository.dart';
import 'chapter_commit.dart';
import 'offline_database.dart';
import 'offline_page_store.dart';
import 'offline_paths.dart';
import 'offline_runtime_storage.dart';
import 'offline_server_identity.dart';
import 'offline_server_identity_repository.dart';
import 'offline_storage_identity.dart';
import 'offline_sync.dart';

part 'offline_repository.g.dart';

class OfflineRepository {
  const OfflineRepository({required this.db, required this.paths});

  final OfflineDatabase db;
  final OfflinePaths paths;

  /// Null if no downloaded page exists.
  Future<String?> localPagePath(int chapterId, int pageIndex) async {
    final rows =
        await (db.select(db.offlinePages)..where(
              (t) =>
                  t.chapterId.equals(chapterId) & t.pageIndex.equals(pageIndex),
            ))
            .get();
    if (rows.isEmpty) return null;
    return paths.absolute(rows.single.relativePath);
  }

  /// Ordered absolute paths, or null unless the chapter is fully downloaded.
  Future<List<String>?> localChapterPages(int chapterId) async {
    final ch = await (db.select(
      db.offlineChapters,
    )..where((t) => t.id.equals(chapterId))).getSingleOrNull();
    if (ch == null || ch.deviceState != OfflineDeviceState.downloaded) {
      return null;
    }
    final rows =
        await (db.select(db.offlinePages)
              ..where((t) => t.chapterId.equals(chapterId))
              ..orderBy([(t) => OrderingTerm(expression: t.pageIndex)]))
            .get();
    if (rows.isEmpty) return null;
    return [for (final r in rows) paths.absolute(r.relativePath)];
  }

  Future<OfflineManga?> mangaById(int mangaId) => db.mangaById(mangaId);

  /// Null if the chapter has not been synced.
  Future<OfflineChapter?> chapterById(int chapterId) => (db.select(
    db.offlineChapters,
  )..where((t) => t.id.equals(chapterId))).getSingleOrNull();

  Future<int> deviceDownloadedCount(List<int> chapterIds) async {
    if (chapterIds.isEmpty) return 0;
    final rows =
        await (db.select(db.offlineChapters)..where(
              (t) =>
                  t.id.isIn(chapterIds) &
                  t.deviceState.equalsValue(OfflineDeviceState.downloaded),
            ))
            .get();
    return rows.length;
  }

  Stream<OfflineDeviceState> watchChapterState(
    int chapterId,
  ) => (db.select(db.offlineChapters)..where((t) => t.id.equals(chapterId)))
      .watchSingleOrNull()
      .map((c) => c?.deviceState ?? OfflineDeviceState.none)
      // Drift emits on any chapter-table write; distinct avoids unrelated row rebuilds.
      .distinct();

  Stream<int> watchChapterDownloadedPages(int chapterId) {
    final cnt = db.offlinePages.pageIndex.count();
    return (db.selectOnly(db.offlinePages)
          ..addColumns([cnt])
          ..where(db.offlinePages.chapterId.equals(chapterId)))
        .watchSingle()
        .map((r) => r.read(cnt) ?? 0)
        .distinct();
  }

  /// Defaults to off when the manga is not synced.
  Future<OfflineKeepRule> keepRuleFor(int mangaId) async {
    final m = await (db.select(
      db.offlineMangas,
    )..where((t) => t.id.equals(mangaId))).getSingleOrNull();
    return m?.keepRule ?? OfflineKeepRule.off;
  }

  Future<({OfflineKeepRule rule, int count})> keepConfigFor(int mangaId) async {
    final m = await (db.select(
      db.offlineMangas,
    )..where((t) => t.id.equals(mangaId))).getSingleOrNull();
    return (
      rule: m?.keepRule ?? OfflineKeepRule.off,
      count: m?.keepUnreadCount ?? 5,
    );
  }

  Future<Set<int>> deviceDownloadedMangaIds() =>
      db.mangaIdsWithDeviceDownloads();

  Stream<Set<int>> watchDeviceDownloadedMangaIds() =>
      db.watchMangaIdsWithDeviceDownloads();

  Future<int> totalDownloadedBytes() => db.totalDownloadedBytes();

  Future<int> downloadedBytesForManga(int mangaId) =>
      db.downloadedBytesForManga(mangaId);
}

@riverpod
OfflineDatabase offlineDatabase(Ref ref) =>
    ref.watch(offlineRuntimeStorageProvider)?.db ??
    (throw StateError('Offline storage is unavailable'));

@riverpod
OfflinePaths offlinePaths(Ref ref) =>
    ref.watch(offlineRuntimeStorageProvider)?.paths ??
    (throw StateError('Offline storage is unavailable'));

@riverpod
OfflinePageStore offlinePageStore(Ref ref) =>
    ref.watch(offlineRuntimeStorageProvider)?.store ??
    (throw StateError('Offline storage is unavailable'));

@riverpod
OfflineRepository offlineRepository(Ref ref) => OfflineRepository(
  db: ref.watch(offlineDatabaseProvider),
  paths: ref.watch(offlinePathsProvider),
);

/// Rebuilds missing page rows from verified files, or re-queues when completeness cannot be proven.
Future<List<String>?> repairDownloadedChapterPages({
  required OfflineDatabase db,
  required OfflinePageStore store,
  required OfflinePaths paths,
  required int chapterId,
  // Re-queueing must also trigger downloading rather than wait for unrelated work.
  void Function()? onRequeued,
}) => ChapterFileLock.run(chapterId, () async {
  final ch = await db.chapterById(chapterId);
  if (ch == null || ch.deviceState != OfflineDeviceState.downloaded) {
    return null;
  }

  final committed = await store.committedPages(ch.mangaId, chapterId);
  // A positive pageCount makes a short directory incomplete; zero means unknown length.
  final short = ch.pageCount > 0 && committed.length < ch.pageCount;
  if (committed.isEmpty || short) {
    logger.w(
      'Offline: chapter $chapterId claims downloaded with '
      '${committed.length}/${ch.pageCount} pages on disk, re-queueing',
    );
    await db.transaction(() async {
      final current = await db.chapterById(chapterId);
      if (current == null ||
          current.deviceState != OfflineDeviceState.downloaded ||
          current.downloadGeneration != ch.downloadGeneration) {
        return;
      }
      await db.bumpChapterGeneration(chapterId);
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
});

@riverpod
bool offlineEnabled(Ref ref) =>
    ref.watch(offlineRuntimeStorageProvider) != null;

@riverpod
bool offlineActive(Ref ref) {
  ref.watch(authCredentialsStoreProvider);
  if (!ref.read(authCredentialsStoreProvider.notifier).sessionAdmitted) {
    return false;
  }
  if (!ref.watch(offlineEnabledProvider)) return false;
  final stamp = ref
      .watch(sharedPreferencesProvider)
      .getString(
        offlineCatalogServerIdKey(ref.read(sharedPreferencesProvider)),
      );
  final current = ref.watch(serverInstanceIdProvider).value;
  if (current == null) return false;
  return isOfflineCatalogActive(
    offlineEnabled: true,
    catalogServer: stamp,
    currentServer: current,
  );
}

final offlineServerAccessProvider = Provider<bool>((ref) {
  if (!ref.watch(offlineActiveProvider)) return false;
  if (ref.watch(authTypeKeyProvider) != AuthType.uiLogin) return true;
  final binding = ref.watch(authCredentialsStoreProvider).value?.accountBinding;
  if (binding == null) return false;
  final verified = ref.watch(verifiedServerInstanceIdProvider);
  return !verified.isLoading && verified.asData?.value == binding.catalogId;
});

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
  // Capture before awaiting: the provider can be disposed during the async gap.
  final catalogDb = ref.watch(offlineDatabaseProvider);
  final stampKey = offlineCatalogServerIdKey(preferences);
  final stamp = preferences.getString(stampKey);
  final isCurrent = ref
      .read(authCredentialsStoreProvider.notifier)
      .captureSession();
  final current = await ref.watch(serverInstanceIdProvider.future);
  if (!ref.mounted || !isCurrent()) return null;
  if (stamp == null || stamp == current) return null;
  if (!await catalogDb.hasCatalogData()) {
    if (!ref.mounted || !isCurrent()) return null;
    await preferences.setString(stampKey, current);
    await preferences.remove(DBKeys.offlineServerMismatchDismissedList.name);
    if (ref.mounted) ref.invalidate(offlineActiveProvider);
    return null;
  }
  final key = serverMismatchKey(stamp, current);
  final dismissedKeys =
      preferences.getStringList(
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
  final current =
      preferences.getStringList(
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
  final stamp = ref
      .watch(sharedPreferencesProvider)
      .getString(
        offlineCatalogServerIdKey(ref.read(sharedPreferencesProvider)),
      );
  if (stamp != null && !ref.watch(offlineActiveProvider)) return null;
  return ref.watch(offlineDatabaseProvider);
}

@riverpod
Future<bool> offlineCatalogAvailable(Ref ref) async {
  final db = ref.watch(offlineReadDatabaseProvider);
  if (db == null) return false;
  return (await db.mangaIdsWithDeviceDownloads()).isNotEmpty;
}

/// Null when offline storage is unavailable.
@riverpod
OfflineSync? offlineSync(Ref ref) {
  if (!ref.watch(offlineServerAccessProvider)) return null;
  final current = watchAuthSession(ref);
  final identity = ref.watch(serverInstanceIdProvider).value;
  if (identity == null) return null;
  final preferences = ref.watch(sharedPreferencesProvider);
  final mangaRepository = ref.watch(mangaBookRepositoryProvider);
  final stampKey = offlineCatalogServerIdKey(preferences);
  return OfflineSync(
    ref.watch(offlineDatabaseProvider),
    taskTracker: ref.read(offlineRuntimeStorageProvider.notifier).track,
    isCurrentSession: current,
    refetchManga: (mangaId) async {
      if (!current()) return null;
      return mangaRepository.getManga(mangaId: mangaId);
    },
    onSynced: () async {
      if (!current()) return;
      if (preferences.getString(stampKey) == null) {
        await preferences.setString(stampKey, identity);
        // Sync callbacks may outlive the provider that captured them.
        if (ref.mounted) ref.invalidate(offlineActiveProvider);
      }
    },
  );
}
