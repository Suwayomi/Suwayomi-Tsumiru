// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/db_keys.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/logger/logger.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../manga_book/data/downloads/downloads_repository.dart';
import '../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../manga_book/data/updates/updates_repository.dart';
import '../../manga_book/presentation/downloads/controller/downloads_controller.dart';
import '../../settings/presentation/downloads/data/delete_chapters_settings_repository.dart';
import 'background/background_download_controller_shim.dart';
import 'background/background_download_lock.dart';
import 'background/catchup_spec_writer.dart';
import 'background/catchup_work_spec.dart';
import 'offline_awaiting_server_downloads.dart';
import 'offline_background_downloads.dart';
import 'offline_database.dart';
import 'offline_download_permission.dart';
import 'offline_download_providers.dart';
import 'offline_repository.dart';
import 'offline_runtime_storage.dart';
import 'offline_storage_identity.dart';
import 'offline_types.dart';


// Feed-page budget; unreached watermarks fall back to a full keep-rule pass.
const _maxCatchUpPages = 3;

bool _running = false;
final _subscriptions = <ProviderSubscription<Object?>>[];

void detachChapterCatchUp() {
  for (final subscription in _subscriptions) {
    subscription.close();
  }
  _subscriptions.clear();
}

void resetChapterCatchUp() {
  if (_running) throw StateError('Chapter catch-up is still running');
  _drainMissedDuringPass = false;
  awaitingServerDownloads.clear();
}

// Replay drains received mid-pass so newly server-downloaded chapters are pulled promptly.
bool _drainMissedDuringPass = false;

@visibleForTesting
void resetChapterCatchUpStateForTest() {
  _running = false;
  _drainMissedDuringPass = false;
  awaitingServerDownloads.clear();
}

@visibleForTesting
void seedAwaitingServerDownloadsForTest(Iterable<int> mangaIds) {
  awaitingServerDownloads
    ..clear()
    ..addAll(mangaIds);
}

@visibleForTesting
void simulateQueueDrainForTest(ProviderContainer container) {
  if (_running) {
    _drainMissedDuringPass = true;
  } else {
    unawaited(pullAfterServerDownloads(container));
  }
}

void initChapterCatchUp(ProviderContainer container) {
  detachChapterCatchUp();
  resetChapterCatchUp();
  // Persist second-hop obligations because the watermark has already passed these manga.
  awaitingServerDownloads.addAll(
    container
            .read(sharedPreferencesProvider)
            .getStringList(
              offlinePreferenceKey(
                container.read,
                DBKeys.offlineCatchUpAwaitingPull,
              ),
            )
            ?.map(int.tryParse)
            .whereType<int>() ??
        const [],
  );
  unawaited(adoptWorkerObligations(container.read));
  final updateSubscription = container.listen(updateRunningSocketProvider, (
    previous,
    next,
  ) {
    final wasRunning = previous?.value ?? false;
    final isRunning = next.value ?? wasRunning;
    if (wasRunning && !isRunning) {
      unawaited(runKeepRuleCatchUp(container));
    }
  });
  _subscriptions.add(updateSubscription);
  final downloadSubscription = container.listen(downloadsMapProvider, (
    previous,
    next,
  ) {
    if ((previous?.isNotEmpty ?? false) && next.isEmpty) {
      if (_running) {
        _drainMissedDuringPass = true;
      } else {
        unawaited(pullAfterServerDownloads(container));
      }
    }
  });
  _subscriptions.add(downloadSubscription);
  unawaited(runKeepRuleCatchUp(container));
}

/// Reads the worker ledger under its lock with freshly reloaded preferences.
Future<bool> adoptWorkerObligations(OfflineRead read) => read(
  offlineRuntimeStorageProvider.notifier,
).track(() => _runWorkerObligations(read));

Future<bool> _runWorkerObligations(OfflineRead read) async {
  final current = read(authCredentialsStoreProvider.notifier).captureSession();
  if (!current() || !downloadPermissionAllowed(read)) return false;
  try {
    final catalogServerId = read(
      sharedPreferencesProvider,
    ).getString(offlineCatalogServerIdKey(read(sharedPreferencesProvider)));
    if (catalogServerId == null) return true;
    final paths = read(offlinePathsProvider);
    final catchupStore = await CatchupStateStore.open();
    if (!current()) return false;
    final ledger = catchupStore.readLedger(catalogServerId);
    if (ledger.pendingServerFetch.isEmpty &&
        ledger.pendingDownloads.isEmpty &&
        ledger.queuedServerRetries.isEmpty &&
        ledger.queuedDownloadRetries.isEmpty) {
      return true;
    }

    final alreadyOwned =
        read(backgroundDownloadControllerProvider).ownedStorageRoot ==
        paths.baseDir;
    final lock = alreadyOwned
        ? null
        : BackgroundDownloadLock(File('${paths.baseDir}/.bg_lock'));
    // Ask the active worker to yield ownership before retrying the lock.
    if (lock != null) {
      var acquired = await lock.acquire('handoff');
      if (!acquired) await lock.requestYield();
      for (var i = 0; !acquired && i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!current()) return false;
        acquired = await lock.acquire('handoff');
        if (!acquired) await lock.requestYield();
      }
      if (!acquired) return false;
    }
    try {
      // Reload preferences inside the lock to include the last worker write.
      final lockedStore = await CatchupStateStore.open();
      if (!current()) return false;
      final fresh = lockedStore.readLedger(catalogServerId);
      if (fresh.pendingServerFetch.isEmpty &&
          fresh.pendingDownloads.isEmpty &&
          fresh.queuedServerRetries.isEmpty &&
          fresh.queuedDownloadRetries.isEmpty) {
        return true;
      }
      awaitingServerDownloads.addAll(fresh.pendingServerFetch.values);
      await persistAwaitingServerDownloads(read);
      if (!current()) return false;
      final pending = {...fresh.pendingServerFetch};
      final retries = {...fresh.serverFetchRetries};
      final generations = {...fresh.chapterGenerations};
      final devicePending = {...fresh.pendingDownloads};
      final deviceRetries = {...fresh.downloadRetries};
      final queuedServerRetries = {...fresh.queuedServerRetries};
      final queuedDownloadRetries = {...fresh.queuedDownloadRetries};
      final db = read(offlineDatabaseProvider);
      await db.transaction(() async {
        for (final entry in fresh.pendingDownloads.entries) {
          if ((deviceRetries[entry.key] ?? 0) < catchupMaxChapterAttempts) {
            continue;
          }
          if (!current()) throw StateError('Authentication session changed');
          final chapter = await db.chapterById(entry.key);
          if (chapter == null) continue;
          if (chapter.mangaId == entry.value &&
              chapter.downloadGeneration ==
                  (fresh.chapterGenerations[entry.key] ?? 0) &&
              chapter.deviceState != OfflineDeviceState.downloaded) {
            await db.setChapterDeviceState(entry.key, OfflineDeviceState.error);
          }
          devicePending.remove(entry.key);
          deviceRetries.remove(entry.key);
          if (!pending.containsKey(entry.key) &&
              !retries.containsKey(entry.key)) {
            generations.remove(entry.key);
          }
        }
        for (final entry in {
          ...fresh.pendingServerFetch,
          for (final entry in fresh.pendingDownloads.entries)
            if (fresh.serverFetchRetries.containsKey(entry.key))
              entry.key: entry.value,
        }.entries) {
          if (!current()) throw StateError('Authentication session changed');
          final chapter = await db.chapterById(entry.key);
          if (chapter == null) continue;
          if (chapter.mangaId == entry.value &&
              chapter.downloadGeneration ==
                  (fresh.chapterGenerations[entry.key] ?? 0) &&
              chapter.deviceState != OfflineDeviceState.downloaded) {
            final spent = retries[entry.key] ?? 0;
            for (
              var count = chapter.serverFetchAttempts;
              count < spent;
              count++
            ) {
              await db.incrementServerFetchAttempts(entry.key);
            }
          }
          pending.remove(entry.key);
          retries.remove(entry.key);
          if (!devicePending.containsKey(entry.key) &&
              !deviceRetries.containsKey(entry.key)) {
            generations.remove(entry.key);
          }
        }
        for (final key in {
          ...fresh.queuedServerRetries.keys,
          ...fresh.queuedDownloadRetries.keys,
        }) {
          if (!current()) throw StateError('Authentication session changed');
          final parts = key.split(':');
          if (parts.length != 2) continue;
          final chapterId = int.tryParse(parts[0]);
          final generation = int.tryParse(parts[1]);
          if (chapterId == null || generation == null) continue;
          final chapter = await db.chapterById(chapterId);
          if (chapter == null) continue;
          if (!current()) throw StateError('Authentication session changed');
          final ownsChapter =
              chapter.downloadGeneration == generation &&
              chapter.deviceState != OfflineDeviceState.downloaded;
          final spent = queuedServerRetries[key] ?? 0;
          if (ownsChapter) {
            for (
              var count = chapter.serverFetchAttempts;
              count < spent;
              count++
            ) {
              await db.incrementServerFetchAttempts(chapterId);
            }
          }
          queuedServerRetries.remove(key);
          if ((queuedDownloadRetries[key] ?? 0) >= catchupMaxChapterAttempts) {
            if (ownsChapter) {
              await db.setChapterDeviceState(
                chapterId,
                OfflineDeviceState.error,
              );
            }
            queuedDownloadRetries.remove(key);
          }
        }
      });
      if (!current()) return false;
      if (!await writeCatchupWorkSpec(read) || !current()) return false;
      await lockedStore.writeLedger(
        catalogServerId,
        fresh.copyWith(
          chapterGenerations: generations,
          pendingDownloads: devicePending,
          downloadRetries: deviceRetries,
          pendingServerFetch: pending,
          serverFetchRetries: retries,
          queuedServerRetries: queuedServerRetries,
          queuedDownloadRetries: queuedDownloadRetries,
        ),
      );
    } finally {
      await lock?.release();
    }
    return true;
  } catch (e) {
    logger.w('Offline: adopting worker obligations failed: $e');
    return false;
  }
}

/// Single-flight; update triggers wait for the next pass, while drain events replay at this pass end.
Future<void> runKeepRuleCatchUp(ProviderContainer container) => container
    .read(offlineRuntimeStorageProvider.notifier)
    .track(() => _runRunKeepRuleCatchUp(container));

Future<void> _runRunKeepRuleCatchUp(ProviderContainer container) async {
  final current = container
      .read(authCredentialsStoreProvider.notifier)
      .captureSession();
  if (!current() || !downloadPermissionAllowed(container.read)) return;
  if (_running) return;
  if (!container.read(offlineServerAccessProvider)) return;
  _running = true;
  try {
    final keepRuleManga = {
      for (final m
          in await container.read(offlineDatabaseProvider).libraryManga())
        if (m.keepRule != OfflineKeepRule.off) m.id,
    };
    if (!current()) return;
    if (keepRuleManga.isEmpty) {
      if (current() && _drainMissedDuringPass) {
        _drainMissedDuringPass = false;
        await _pullAwaiting(container, current);
      }
      return;
    }

    final prefs = container.read(sharedPreferencesProvider);
    final watermark =
        prefs.getInt(
          offlinePreferenceKey(container.read, DBKeys.offlineCatchUpWatermark),
        ) ??
        0;

    final scan = await touchedSinceWatermark(
      fetchPage: (pageNo) async {
        if (!current()) return null;
        final page = await container
            .read(updatesRepositoryProvider)
            .getRecentChaptersPage(pageNo: pageNo);
        final nodes = page?.nodes;
        if (nodes == null) return null;
        return [
          for (final n in nodes)
            (mangaId: n.mangaId, fetchedAt: int.tryParse(n.fetchedAt) ?? 0),
        ];
      },
      keepRuleManga: keepRuleManga,
      watermark: watermark,
    );
    if (!current()) return;
    final feedTouched = scan.sawWatermark ? scan.touched : keepRuleManga;
    // Server download state can change without a feed entry; always revisit outstanding pulls.
    final touched = {
      ...feedTouched,
      ...awaitingServerDownloads.where(keepRuleManga.contains),
    };
    final allSynced = await _syncAndReconcile(container, touched, current);

    // Advance the watermark only after every manga succeeds so skipped work remains retryable.
    if (!current()) return;
    if (allSynced && scan.newestFetchedAt > watermark) {
      await prefs.setInt(
        offlinePreferenceKey(container.read, DBKeys.offlineCatchUpWatermark),
        scan.newestFetchedAt,
      );
    }
    if (!current()) return;
    if (touched.isNotEmpty) {
      await container.read(downloadStarterProvider)();
    }
    await _pullAwaiting(container, current, skip: touched);
    // Replay a drain deferred during this pass so newly available server copies are not stranded.
    if (current() && _drainMissedDuringPass) {
      _drainMissedDuringPass = false;
      await _pullAwaiting(container, current);
    }
    if (!current()) return;
    await writeCatchupWorkSpec(container.read);
  } catch (e) {
    logger.w('Offline: chapter catch-up pass failed: $e');
  } finally {
    _running = false;
  }
}

/// Pulls server-fetch obligations after queue drain; mid-pass drain events replay at pass end.
Future<void> pullAfterServerDownloads(ProviderContainer container) => container
    .read(offlineRuntimeStorageProvider.notifier)
    .track(() => _runPullAfterServerDownloads(container));

Future<void> _runPullAfterServerDownloads(ProviderContainer container) async {
  final current = container
      .read(authCredentialsStoreProvider.notifier)
      .captureSession();
  if (!current() || !downloadPermissionAllowed(container.read)) return;
  if (_running) return;
  _running = true;
  try {
    await _pullAwaiting(container, current);
    if (current() && _drainMissedDuringPass) {
      _drainMissedDuringPass = false;
      await _pullAwaiting(container, current);
    }
  } finally {
    _running = false;
  }
}

Future<void> _pullAwaiting(
  ProviderContainer container,
  bool Function() current, {
  Set<int> skip = const {},
}) async {
  if (!current() || !downloadPermissionAllowed(container.read)) return;
  if (awaitingServerDownloads.isEmpty) return;
  if (!container.read(offlineServerAccessProvider)) return;
  var pulled = false;
  // Persist each consumed obligation separately so a crash preserves the unprocessed remainder.
  for (final mangaId in {...awaitingServerDownloads}) {
    if (!current() || !downloadPermissionAllowed(container.read)) return;
    if (skip.contains(mangaId)) continue;
    pulled = true;
    awaitingServerDownloads.remove(mangaId);
    // Reconciliation may create a fresh obligation for the same manga; preserve it.
    final ok = await _syncAndReconcile(container, {mangaId}, current);
    if (!current()) return;
    if (!ok) awaitingServerDownloads.add(mangaId);
    await persistAwaitingServerDownloads(container.read);
  }
  if (!current()) return;
  if (pulled) await container.read(downloadStarterProvider)();
}

/// Re-includes watermark-second ties; sawWatermark false means the unscanned tail is unknown.
@visibleForTesting
Future<({Set<int> touched, int newestFetchedAt, bool sawWatermark})>
touchedSinceWatermark({
  required Future<List<({int mangaId, int fetchedAt})>?> Function(int pageNo)
  fetchPage,
  required Set<int> keepRuleManga,
  required int watermark,
}) async {
  final touched = <int>{};
  var newest = watermark;
  // First run seeds one page, then falls back to the full keep-rule pass.
  final pageBudget = watermark == 0 ? 1 : _maxCatchUpPages;
  for (var page = 0; page < pageBudget; page++) {
    final nodes = await fetchPage(page);
    if (nodes == null) break;
    if (nodes.isEmpty) {
      return (touched: touched, newestFetchedAt: newest, sawWatermark: true);
    }
    for (final node in nodes) {
      if (node.fetchedAt < watermark) {
        return (touched: touched, newestFetchedAt: newest, sawWatermark: true);
      }
      newest = math.max(newest, node.fetchedAt);
      if (keepRuleManga.contains(node.mangaId)) touched.add(node.mangaId);
    }
    if (nodes.length < updatesPageSize) {
      return (touched: touched, newestFetchedAt: newest, sawWatermark: true);
    }
  }
  return (touched: touched, newestFetchedAt: newest, sawWatermark: false);
}

/// Fetches fresh server state before reconciling; stale isDownloaded flags can misroute either hop.
/// Starts queued downloads immediately after reconciliation.
Future<void> syncAndReconcileMangaSet(
  ProviderContainer container,
  Set<int> mangaIds, {
  bool userInitiated = false,
}) async {
  if (mangaIds.isEmpty) return;
  if (!container.read(offlineActiveProvider)) return;
  final current = container
      .read(authCredentialsStoreProvider.notifier)
      .captureSession();
  if (!current() || !downloadPermissionAllowed(container.read)) return;
  await _syncAndReconcile(container, mangaIds, current);
  if (!current()) return;
  try {
    await writeCatchupWorkSpec(container.read);
  } catch (e) {
    logger.w('Offline: work spec after bulk keep-rule change failed: $e');
  }
  if (!current()) return;
  await container.read(downloadStarterProvider)(userInitiated: userInitiated);
}

// Process manga sequentially to keep a large catch-up behind the UI.
Future<bool> _syncAndReconcile(
  ProviderContainer container,
  Set<int> mangaIds,
  bool Function() current,
) async {
  var allSynced = true;
  for (final mangaId in mangaIds) {
    if (!current()) return false;
    try {
      final sync = container.read(offlineSyncProvider);
      final chapters = await container
          .read(mangaBookRepositoryProvider)
          .getStoredChapterList(mangaId);
      if (!current()) return false;
      if (chapters == null || sync == null) {
        allSynced = false;
        continue;
      }
      final newlyRead = await sync.syncChapters(chapters);
      if (!current()) return false;
      if (!await _reconcileTracked(
        container,
        mangaId,
        current,
        newlyReadChapterIds: newlyRead,
      )) {
        allSynced = false;
      }
    } catch (e) {
      // Never evict against a chapter list whose fetch failed.
      allSynced = false;
      logger.w('Offline: catch-up skipped manga $mangaId: $e');
    }
  }
  return allSynced;
}

/// Tracks server-fetch obligations; false on failed enqueue prevents watermark advancement.
Future<bool> _reconcileTracked(
  ProviderContainer container,
  int mangaId,
  bool Function() current, {
  Set<int> newlyReadChapterIds = const {},
}) async {
  if (!current() || !downloadPermissionAllowed(container.read)) return false;
  final manager = container.read(offlineDownloadManagerProvider);
  final coordinator = container.read(offlineDownloadCoordinatorProvider);
  if (manager == null || coordinator == null) return false;
  return container.read(backgroundDownloadControllerProvider).withOwnership(
    () async {
      if (!current()) return false;
      if (!await adoptWorkerObligations(container.read)) return false;
      var enqueueFailed = false;
      await reconcileMangaCore(
        verifyPermission: () => verifyDownloadPermission(container.read),
        onPermissionDenied: () async {
          if (current()) await pauseDownloadsForPermission(container.read);
        },
        isCurrent: current,
        db: container.read(offlineDatabaseProvider),
        repo: container.read(offlineRepositoryProvider),
        manager: manager,
        coordinator: coordinator,
        nets: container.read(safetyNetConfigProvider),
        mangaId: mangaId,
        sessionProtected: container.read(sessionReadChaptersProvider),
        deleteWhileReadingSlots: container
            .read(localDeleteSettingsProvider)
            .deleteWhileReading,
        newlyReadChapterIds: newlyReadChapterIds,
        downloadProtectionWindow:
            container.read(localDownloadProtectionWindowProvider) ?? false,
        enqueueServerDownload: (ids) async {
          if (!current()) throw StateError('Authentication session changed');
          try {
            await container
                .read(downloadsRepositoryProvider)
                .addChaptersBatchToDownloadQueue(ids);
            // Failed enqueues create no drain edge to retry an obligation.
            if (!current()) throw StateError('Authentication session changed');
            awaitingServerDownloads.add(mangaId);
          } catch (_) {
            enqueueFailed = true;
            rethrow;
          }
        },
        removeFromWorker: (id, gen) async {
          if (!current()) throw StateError('Authentication session changed');
          final ctrl = container.read(backgroundDownloadControllerProvider);
          await ctrl.onRemoved(id);
          if (!current()) throw StateError('Authentication session changed');
          await ctrl.recordChapterDeleted(id, gen);
        },
      );
      if (!current()) return false;
      await persistAwaitingServerDownloads(container.read);
      return current() && !enqueueFailed;
    },
  );
}
