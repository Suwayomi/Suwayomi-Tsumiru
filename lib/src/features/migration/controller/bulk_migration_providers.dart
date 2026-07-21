// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../auth/data/auth_state.dart';
import '../../browse_center/presentation/source/controller/source_controller.dart';
import '../../library/presentation/library/controller/library_manga_list.dart';
import '../../manga_book/data/downloads/downloads_repository.dart';
import '../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../manga_book/domain/chapter/chapter_model.dart';
import '../../offline/data/offline_background_downloads.dart';
import '../../offline/data/offline_download_providers.dart';
import '../../offline/data/offline_repository.dart';
import '../data/bulk_migration_runner.dart';
import '../data/migration_journal.dart';
import '../data/migration_repository.dart';
import '../data/offline_migration_service.dart';
import '../domain/chapter_matcher.dart';
import '../domain/bulk_migration_types.dart';
import '../domain/concurrency.dart';
import '../domain/library_source_groups.dart';
import '../domain/migration_models.dart';
import '../domain/smart_search_engine.dart';

part 'bulk_migration_providers.g.dart';

/// The library grouped by source, obsolete-first — the source-picker's model.
@riverpod
Future<List<LibrarySourceGroup>> librarySourceGroups(Ref ref) async {
  final mangas = await ref.watch(libraryMangaListProvider.future) ?? const [];
  return groupLibraryBySource([
    for (final m in mangas)
      (
        sourceId: m.sourceId,
        displayName: m.source?.displayName ?? m.sourceId,
        // null source = extension uninstalled/gone; else use its obsolete flag.
        isObsolete: m.source == null || m.source!.$extension.isObsolete,
      ),
  ]);
}

/// Ordered target-source priority (ids, most preferred first); persisted so it
/// sticks between batches.
@riverpod
class MigrationTargetSourcesPref extends _$MigrationTargetSourcesPref
    with SharedPreferenceClientMixin<List<String>> {
  @override
  List<String>? build() => initialize(DBKeys.migrationTargetSources);
}

/// Flushes a source's unsynced offline reads (progress only, no tracker nudge)
/// then reports whether it's clean; migration blocks removal when this is false.
Future<bool> bulkMigrationDirtyGate(
    ProviderContainer container, int mangaId, CancelToken token) async {
  if (!container.read(offlineActiveProvider)) return true;
  try {
    await pushPendingProgress(container, suppressTrackerNudge: true);
  } catch (_) {
    // A failed flush (e.g. offline) leaves the source dirty — reported below.
  }
  final db = container.read(offlineDatabaseProvider);
  final dirty = await db.dirtyChapters();
  return !dirty.any((c) => c.mangaId == mangaId);
}

/// Blocks while a 401 wave has flagged reauth, waking when it clears or the
/// batch is cancelled. Re-checks on a 1s heartbeat in case the listener misses.
Future<void> waitAuthReady(
    ProviderContainer container, CancelToken token) async {
  while (!token.isCancelled && container.read(needsReauthProvider)) {
    final completer = Completer<void>();
    final sub = container.listen<bool>(needsReauthProvider, (_, next) {
      if (!next && !completer.isCompleted) completer.complete();
    });
    await Future.any<void>([
      completer.future,
      token.whenCancelled,
      Future<void>.delayed(const Duration(seconds: 1)),
    ]);
    sub.close();
  }
}

/// Drains any crash-recovery journal from a batch killed mid-run, called once
/// at launch so it actually self-heals instead of only running in tests.
/// Best-effort — a failure must never block startup.
Future<void> recoverBulkMigrationsAtLaunch(ProviderContainer container) async {
  try {
    await recoverMigrationJournal(
      repo: container.read(migrationRepositoryProvider),
      journal: MigrationJournal(container.read(sharedPreferencesProvider)),
    );
  } catch (_) {
    // Never let migration recovery break app launch.
  }
}

/// Carries device-local offline state (keep-rule + downloaded files) onto the
/// migration target, reusing the app's real offline machinery. No-op when
/// offline is inactive. Best-effort — the runner swallows failures.
Future<void> migrateOfflineLocalState(
  ProviderContainer container,
  int fromMangaId,
  int toMangaId,
  MigrationOption options,
) async {
  // Server-side downloads carry regardless of device-offline availability: tell
  // the server to download the target's matching chapters so it's downloaded
  // server-side too, not just on this device.
  if (options.migrateDownloads) {
    await _migrateServerDownloads(container, fromMangaId, toMangaId);
  }
  if (!container.read(offlineActiveProvider)) return;
  final sync = container.read(offlineSyncProvider);
  final manager = container.read(offlineDownloadManagerProvider);
  final coordinator = container.read(offlineDownloadCoordinatorProvider);
  if (sync == null || manager == null || coordinator == null) return;
  final mangaRepo = container.read(mangaBookRepositoryProvider);
  final service = OfflineMigrationService(
    db: container.read(offlineDatabaseProvider),
    pageStore: container.read(offlinePageStoreProvider),
    sync: sync,
    fetchManga: (id) => mangaRepo.getManga(mangaId: id),
    fetchChapters: (id) => mangaRepo.getChapterList(id),
    reconcileTarget: (id) async {
      await reconcileMangaCore(
        db: container.read(offlineDatabaseProvider),
        repo: container.read(offlineRepositoryProvider),
        manager: manager,
        coordinator: coordinator,
        nets: container.read(safetyNetConfigProvider),
        mangaId: id,
        enqueueServerDownload: (ids) => container
            .read(downloadsRepositoryProvider)
            .addChaptersBatchToDownloadQueue(ids),
      );
      await container.read(downloadStarterProvider)();
    },
  );
  await service.migrate(
    fromMangaId: fromMangaId,
    toMangaId: toMangaId,
    options: options,
  );
}

/// Enqueues server downloads for the target's chapters that match the source's
/// server-downloaded ones (by number) — so a migrated series is downloaded on
/// the server, not only on the device that ran the migration.
Future<void> _migrateServerDownloads(
    ProviderContainer container, int fromMangaId, int toMangaId) async {
  try {
    final repo = container.read(mangaBookRepositoryProvider);
    final source = await repo.getChapterList(fromMangaId) ?? const [];
    final target = await repo.getChapterList(toMangaId) ?? const [];
    final pairs = matchChaptersByNumber(
      source: [for (final c in source) if (c.isDownloaded) _chapterState(c)],
      target: [for (final c in target) _chapterState(c)],
    );
    if (pairs.isEmpty) return;
    await container
        .read(downloadsRepositoryProvider)
        .addChaptersBatchToDownloadQueue([for (final p in pairs) p.toId]);
  } catch (_) {
    // Best-effort — a missed server download re-downloads on demand later.
  }
}

ChapterState _chapterState(ChapterDto c) => ChapterState(
      id: c.id,
      chapterNumber: c.chapterNumber,
      name: c.name,
      isRead: c.isRead,
      isBookmarked: c.isBookmarked,
      lastPageRead: c.lastPageRead,
    );

/// Assembles a [BulkMigrationRunner] from the app's real dependencies. Holds a
/// container (not a Ref) so it survives navigation; the screen owns its lifetime.
BulkMigrationRunner buildBulkMigrationRunner({
  required ProviderContainer container,
  required List<BulkMigrationEntry> entries,
  required List<String> targetSourceIds,
  required MigrationOption options,
  String? extraSearchQuery,
  Future<void> Function(int fromMangaId)? onSourceRemoved,
}) {
  final repo = container.read(migrationRepositoryProvider);
  final journal = MigrationJournal(container.read(sharedPreferencesProvider));
  final rateLimiter =
      RateLimiter(minInterval: const Duration(milliseconds: 250));
  final allSources =
      container.read(searchableSourcesProvider).value ?? const [];
  final sourceNames = {for (final s in allSources) s.id: s.displayName};
  final matcher = buildSmartMatcher(
    targetSourceIds: targetSourceIds,
    rateLimiter: rateLimiter,
    sourceNames: sourceNames,
    engine: SmartSearchEngine(extraSearchParams: extraSearchQuery),
    search: (sourceId, query) async {
      final results = await repo.searchMangaInSource(sourceId, query);
      return [
        for (final m in results ?? const [])
          (id: m.id, title: m.title, thumbnailUrl: m.thumbnailUrl),
      ];
    },
  );
  return BulkMigrationRunner(
    repo: repo,
    journal: journal,
    options: options,
    entries: entries,
    matcher: matcher,
    rateLimiter: rateLimiter,
    dirtyGate: (id, token) => bulkMigrationDirtyGate(container, id, token),
    isReauthNeeded: () => container.read(needsReauthProvider),
    waitAuthReady: (token) => waitAuthReady(container, token),
    onSourceRemoved: onSourceRemoved,
    migrateLocalState: (fromId, toId, opts) =>
        migrateOfflineLocalState(container, fromId, toId, opts),
  );
}
