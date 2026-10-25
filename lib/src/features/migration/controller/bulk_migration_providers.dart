// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../utils/mixin/state_provider_mixin.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../auth/data/auth_state.dart';
import '../../browse_center/domain/source/source_model.dart';
import '../../library/presentation/library/controller/library_manga_list.dart';
import '../../manga_book/data/downloads/downloads_repository.dart';
import '../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../manga_book/domain/chapter/chapter_model.dart';
import '../../manga_book/presentation/downloads/controller/downloads_controller.dart';
import '../../offline/data/background/background_download_controller_shim.dart';
import '../../offline/data/background/catchup_work_spec.dart';
import '../../offline/data/offline_background_downloads.dart';
import '../../offline/data/offline_chapter_catchup.dart';
import '../../offline/data/offline_download_permission.dart';
import '../../offline/data/offline_download_providers.dart';
import '../../offline/data/offline_repository.dart';
import '../../offline/data/offline_runtime_storage.dart';
import '../../offline/data/offline_server_identity_repository.dart';
import '../../settings/presentation/downloads/data/delete_chapters_settings_repository.dart';
import '../../settings/presentation/general/timeout_settings/timeout_settings_section.dart';
import '../data/bulk_migration_runner.dart';
import '../data/migration_journal.dart';
import '../data/migration_repository.dart';
import '../data/offline_migration_service.dart';
import '../domain/bulk_migration_types.dart';
import '../domain/chapter_matcher.dart';
import '../domain/concurrency.dart';
import '../domain/library_source_groups.dart';
import '../domain/migration_models.dart';
import '../domain/smart_search_engine.dart';

part 'bulk_migration_providers.g.dart';

bool Function() _captureSession(ProviderContainer container) {
  final auth = container.read(authCredentialsStoreProvider.notifier);
  final epoch = auth.sessionEpoch;
  final preferences = container.read(sharedPreferencesProvider);
  final controls = CatchupStateStore(preferences);
  return () =>
      !auth.sessionChanging &&
      auth.sessionEpoch == epoch &&
      preferences.getBool(CatchupStateStore.identityAuthorizedKey) == true &&
      !controls.identityChanging;
}

MigrationJournal _accountJournal(ProviderContainer container) {
  if (!_captureSession(container)()) {
    throw StateError('Account identity is not verified');
  }
  String? accountId;
  if (container.read(authTypeKeyProvider) == AuthType.uiLogin) {
    final state = container.read(authCredentialsStoreProvider);
    if (!state.isLoading && !state.hasError) {
      accountId = state.value?.accountBinding?.catalogId;
    }
  } else {
    final identity = container.read(serverInstanceIdProvider);
    if (!identity.isLoading && !identity.hasError) accountId = identity.value;
  }
  if (accountId == null || accountId.isEmpty) {
    throw StateError('Account identity is not verified');
  }
  return MigrationJournal(
    container.read(sharedPreferencesProvider),
    accountId: accountId,
  );
}

@riverpod
Future<List<LibrarySourceGroup>> librarySourceGroups(Ref ref) async {
  final mangas = await ref.watch(libraryMangaListProvider.future) ?? const [];
  return groupLibraryBySource([
    for (final m in mangas)
      (
        sourceId: m.sourceId,
        displayName: m.source?.displayName ?? m.sourceId,
        isObsolete: m.source == null || m.source!.$extension.isObsolete,
      ),
  ]);
}

@riverpod
class MigrationSourcePickerQuery extends _$MigrationSourcePickerQuery
    with StateProviderMixin<String> {
  @override
  String build() => '';
}

/// Persists target-source IDs in descending preference order.
@riverpod
class MigrationTargetSourcesPref extends _$MigrationTargetSourcesPref
    with SharedPreferenceClientMixin<List<String>> {
  @override
  List<String>? build() => initialize(DBKeys.migrationTargetSources);
}

/// Flushes offline progress without tracker updates; false blocks source removal.
Future<bool> bulkMigrationDirtyGate(
  ProviderContainer container,
  int mangaId,
  CancelToken token,
) {
  final current = _captureSession(container);
  return container.read(offlineRuntimeStorageProvider.notifier).track(() async {
    if (!current() || token.isCancelled) return false;
    try {
      _accountJournal(container);
    } catch (_) {
      return false;
    }
    if (!container.read(offlineActiveProvider)) return true;
    final db = container.read(offlineDatabaseProvider);
    try {
      await pushPendingProgress(container, suppressTrackerNudge: true);
    } catch (_) {}
    if (!current() || token.isCancelled) return false;
    final dirty = await db.dirtyChapters();
    return current() &&
        !token.isCancelled &&
        !dirty.any((c) => c.mangaId == mangaId);
  });
}

/// Waits for reauth or cancellation, rechecking every second if the listener misses a change.
Future<void> waitAuthReady(
  ProviderContainer container,
  CancelToken token,
) async {
  final current = _captureSession(container);
  while (current() &&
      !token.isCancelled &&
      container.read(needsReauthProvider)) {
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

/// Recovers an interrupted batch at launch; failures must not block startup.
Future<void> recoverBulkMigrationsAtLaunch(ProviderContainer container) {
  final current = _captureSession(container);
  return container.read(offlineRuntimeStorageProvider.notifier).track(() async {
    if (!current()) return;
    try {
      final journal = _accountJournal(container);
      final repo = container.read(migrationRepositoryProvider);
      await recoverMigrationJournal(
        repo: repo,
        journal: journal,
        isSessionCurrent: current,
        onSourceRemoved: (id) async {
          if (current()) container.invalidate(downloadStatusProvider);
        },
      );
    } catch (_) {}
  });
}

/// Carries offline downloads and keep-rules; inactive offline storage is a no-op.
Future<void> migrateOfflineLocalState(
  ProviderContainer container,
  int fromMangaId,
  int toMangaId,
  MigrationOption options,
) {
  final current = _captureSession(container);
  return container.read(offlineRuntimeStorageProvider.notifier).track(() async {
    if (!current()) return;
    _accountJournal(container);
    final mangaRepo = container.read(mangaBookRepositoryProvider);
    final downloads = container.read(downloadsRepositoryProvider);
    OfflineMigrationService? service;
    if (container.read(offlineActiveProvider)) {
      final sync = container.read(offlineSyncProvider);
      final manager = container.read(offlineDownloadManagerProvider);
      final coordinator = container.read(offlineDownloadCoordinatorProvider);
      if (sync != null && manager != null && coordinator != null) {
        final db = container.read(offlineDatabaseProvider);
        final repository = container.read(offlineRepositoryProvider);
        final nets = container.read(safetyNetConfigProvider);
        final deleteSlots = container
            .read(localDeleteSettingsProvider)
            .deleteWhileReading;
        final starter = container.read(downloadStarterProvider);
        service = OfflineMigrationService(
          withOwnership: container
              .read(backgroundDownloadControllerProvider)
              .withOwnership,
          db: db,
          pageStore: container.read(offlinePageStoreProvider),
          sync: sync,
          fetchManga: (id) {
            if (!current()) throw const CancelledException();
            return mangaRepo.getManga(mangaId: id);
          },
          fetchChapters: (id) {
            if (!current()) throw const CancelledException();
            return id == fromMangaId
                ? mangaRepo.getStoredChapterList(id)
                : mangaRepo.getChapterList(id);
          },
          reconcileTarget: (id) async {
            if (!current() || !downloadPermissionAllowed(container.read)) {
              return;
            }
            final reconciled = await container
                .read(backgroundDownloadControllerProvider)
                .withOwnership(() async {
                  if (!await adoptWorkerObligations(container.read)) {
                    return false;
                  }
                  await reconcileMangaCore(
                    verifyPermission: () =>
                        verifyDownloadPermission(container.read),
                    onPermissionDenied: () async {
                      if (current()) {
                        await pauseDownloadsForPermission(container.read);
                      }
                    },
                    isCurrent: current,
                    db: db,
                    repo: repository,
                    manager: manager,
                    coordinator: coordinator,
                    nets: nets,
                    mangaId: id,
                    deleteWhileReadingSlots: deleteSlots,
                    enqueueServerDownload: (ids) async {
                      if (!current()) return;
                      await downloads.addChaptersBatchToDownloadQueue(ids);
                    },
                  );
                  return true;
                });
            if (reconciled && current()) await starter();
          },
        );
      }
    }
    if (options.migrateDownloads) {
      try {
        final source =
            await mangaRepo.getStoredChapterList(fromMangaId) ?? const [];
        if (!current()) return;
        final target = await mangaRepo.getChapterList(toMangaId) ?? const [];
        if (!current()) return;
        final pairs = matchChaptersByNumber(
          source: [
            for (final c in source)
              if (c.user.isDownloaded) _chapterState(c),
          ],
          target: [for (final c in target) _chapterState(c)],
        );
        if (pairs.isNotEmpty) {
          await downloads.addChaptersBatchToDownloadQueue([
            for (final p in pairs) p.toId,
          ]);
        }
      } catch (_) {}
    }
    if (!current()) return;
    await service?.migrate(
      fromMangaId: fromMangaId,
      toMangaId: toMangaId,
      options: options,
    );
  });
}

ChapterState _chapterState(ChapterDto c) => ChapterState(
  id: c.id,
  chapterNumber: c.chapterNumber,
  name: c.name,
  isRead: c.user.isRead,
  isBookmarked: c.user.isBookmarked,
  lastPageRead: c.user.lastPageRead,
);

/// Holds a container across navigation; the screen owns the runner lifetime.
BulkMigrationRunner buildBulkMigrationRunner({
  required ProviderContainer container,
  required List<BulkMigrationEntry> entries,
  required List<String> targetSourceIds,
  required MigrationOption options,
  List<SourceDto> sources = const [],
  String? extraSearchQuery,
  Future<void> Function(int fromMangaId)? onSourceRemoved,
}) {
  final current = _captureSession(container);
  final journal = _accountJournal(container);
  final repo = container.read(migrationRepositoryProvider);
  final searchTimeout = Duration(
    milliseconds:
        container.read(serverRequestTimeoutProvider) ??
        DBKeys.serverRequestTimeout.initial as int,
  );
  final rateLimiter = RateLimiter(
    minInterval: const Duration(milliseconds: 250),
  );
  final sourceNames = {for (final s in sources) s.id: s.displayName};
  final matcher = buildSmartMatcher(
    targetSourceIds: targetSourceIds,
    rateLimiter: rateLimiter,
    sourceNames: sourceNames,
    engine: SmartSearchEngine(extraSearchParams: extraSearchQuery),
    search: (sourceId, query) async {
      final results = await repo
          .searchMangaInSource(sourceId, query)
          .timeout(searchTimeout, onTimeout: () => []);
      return [
        for (final m in results ?? const [])
          (id: m.id, title: m.title, thumbnailUrl: m.thumbnailUrl),
      ];
    },
  );
  return BulkMigrationRunner(
    repo: repo,
    journal: journal,
    isSessionCurrent: current,
    options: options,
    entries: entries,
    matcher: matcher,
    rateLimiter: rateLimiter,
    dirtyGate: (id, token) => current()
        ? bulkMigrationDirtyGate(container, id, token)
        : Future.value(false),
    isReauthNeeded: () => current() && container.read(needsReauthProvider),
    waitAuthReady: (token) =>
        current() ? waitAuthReady(container, token) : Future.value(),
    onSourceRemoved: (id) async {
      if (!current()) return;
      container.invalidate(downloadStatusProvider);
      await onSourceRemoved?.call(id);
    },
    migrateLocalState: (fromId, toId, opts) => current()
        ? migrateOfflineLocalState(container, fromId, toId, opts)
        : Future.value(),
  );
}
