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
import 'offline_types.dart';

/// Closes the #310 gap: a library update told the SERVER to find new chapters,
/// but nothing on the client synced or downloaded them for keep-rule manga —
/// the full fetch→mirror→reconcile chain only ran on a manga-details visit.

/// Feed pages scanned per pass. Running out of budget before reaching the
/// watermark falls back to a full keep-rule pass, so the cap trades feed
/// queries for chapter-list fetches rather than dropping anything.
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

/// Set by the [downloadsMapProvider] drain listener when a drain event fires
/// while a catch-up pass holds [_running]. Rather than dropping the event, we
/// record it here and replay [_pullAwaiting] at the tail of the current pass so
/// chapters that became serverIsDownloaded during the pass are not stranded
/// until the next update cycle.
bool _drainMissedDuringPass = false;

/// Resets all module-private state, PLUS the cross-module
/// [awaitingServerDownloads] set. These globals persist across `test()` cases
/// in the same file (one isolate per file), so every test exercising this
/// module must call this in `setUp`.
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

/// Test-only mirror of the [downloadsMapProvider] drain listener installed by
/// [initChapterCatchUp]. Lets a test simulate a queue-drain event landing at
/// an arbitrary point in time without wiring up the full listener chain.
@visibleForTesting
void simulateQueueDrainForTest(ProviderContainer container) {
  if (_running) {
    _drainMissedDuringPass = true;
  } else {
    unawaited(pullAfterServerDownloads(container));
  }
}

/// Called once from app bootstrap, after the offline engine is up.
void initChapterCatchUp(ProviderContainer container) {
  detachChapterCatchUp();
  resetChapterCatchUp();
  // Restore the second-hop obligations — the watermark has already moved past
  // these manga, so losing the set to a restart would strand their pulls.
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
  // Adopt the background worker's second-hop obligations: chapters it queued
  // server-side get pulled by the foreground machinery now instead of waiting
  // for the next background wake. Exhausted retries hand off the same way —
  // foreground reconcile owns surfacing stuck downloads.
  unawaited(adoptWorkerObligations(container.read));
  // A finished server update run is the moment new chapters exist to pull.
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
  // The server's download queue draining is the moment chapters queued by a
  // catch-up reconcile become pullable to the device.
  final downloadSubscription = container.listen(downloadsMapProvider, (
    previous,
    next,
  ) {
    if ((previous?.isNotEmpty ?? false) && next.isEmpty) {
      if (_running) {
        // A catch-up pass is in flight — defer rather than drop. The pass's
        // own tail will call _pullAwaiting again with fresh server state.
        _drainMissedDuringPass = true;
      } else {
        unawaited(pullAfterServerDownloads(container));
      }
    }
  });
  _subscriptions.add(downloadSubscription);
  // Catch anything the server found while the app was closed.
  unawaited(runKeepRuleCatchUp(container));
}

/// Read-modify-write on the worker's ledger, so it runs under the download
/// lock (a live worker run means skip — next launch retries) and against a
/// freshly reloaded prefs cache, never this isolate's stale snapshot.
Future<bool> adoptWorkerObligations(OfflineRead read) => read(
  offlineRuntimeStorageProvider.notifier,
).track(() => _runWorkerObligations(read));

Future<bool> _runWorkerObligations(OfflineRead read) async {
  final current = read(authCredentialsStoreProvider.notifier).captureSession();
  if (!current() || !downloadPermissionAllowed(read)) return false;
  try {
    final catalogServerId = read(
      sharedPreferencesProvider,
    ).getString(DBKeys.offlineCatalogServerId.name);
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
    // The worker holds this while it downloads, and a single no-wait attempt
    // made a foreground save fail whenever it landed mid-chapter — reported,
    // wrongly, as an account permission problem. Ask the worker to yield and
    // give it a few seconds, the way the controller's own ownership path does.
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
      // Re-open INSIDE the lock: open() reloads the prefs cache, so the read
      // below cannot predate a worker write that slipped in before acquire.
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

/// Single-flight: an update trigger landing mid-pass is dropped, since its
/// chapters are newer than the watermark and will be picked up by the next
/// pass. A server-download drain event landing mid-pass is instead deferred
/// via [_drainMissedDuringPass] and replayed at the tail of the current pass.
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
    // Didn't reach the watermark (or this is the first pass, with none yet)?
    // Fall back to every keep-rule manga instead of skipping the tail.
    if (!current()) return;
    final feedTouched = scan.sawWatermark ? scan.touched : keepRuleManga;
    // Also include manga still awaiting a server-side download. Their
    // serverIsDownloaded flag can flip without generating a new feed entry
    // (e.g. a manual re-download via the WebUI), so the watermark scan would
    // miss them — always give them a fresh sync attempt.
    final touched = {
      ...feedTouched,
      ...awaitingServerDownloads.where(keepRuleManga.contains),
    };
    final allSynced = await _syncAndReconcile(container, touched, current);

    // Only a fully-processed pass may advance the watermark — a skipped manga
    // must stay newer than it so the next pass retries. syncChapters is
    // idempotent, so re-processing the rest is just cheap.
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
    // If a drain event arrived while this pass was in flight, the listener
    // deferred it instead of dropping it. Re-run the pull now so chapters that
    // became serverIsDownloaded during the pass are not stranded until the next
    // update cycle.
    if (current() && _drainMissedDuringPass) {
      _drainMissedDuringPass = false;
      await _pullAwaiting(container, current);
    }
    // Freshest device-state snapshot for the background worker.
    if (!current()) return;
    await writeCatchupWorkSpec(container.read);
  } catch (e) {
    logger.w('Offline: chapter catch-up pass failed: $e');
  } finally {
    _running = false;
  }
}

/// Second hop: chapters the server had to download from the source first.
/// Once its queue drains, re-run the chain for the manga that were waiting so
/// the device copies get pulled. Single-flight with the catch-up pass; a drain
/// event landing mid-pass sets [_drainMissedDuringPass] instead of being
/// dropped, and is replayed at the pass's tail.
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
  // One obligation at a time, persisted after each: a crash mid-loop keeps
  // the unprocessed rest, and a batch clear would lose them.
  for (final mangaId in {...awaitingServerDownloads}) {
    if (!current() || !downloadPermissionAllowed(container.read)) return;
    if (skip.contains(mangaId)) continue;
    pulled = true;
    awaitingServerDownloads.remove(mangaId);
    // The reconcile may re-add this manga (a NEW server enqueue) — that is a
    // fresh obligation, not the one being consumed, so it must survive.
    final ok = await _syncAndReconcile(container, {mangaId}, current);
    if (!current()) return;
    if (!ok) awaitingServerDownloads.add(mangaId);
    await persistAwaitingServerDownloads(container.read);
  }
  if (!current()) return;
  if (pulled) await container.read(downloadStarterProvider)();
}

/// Scans the feed for keep-rule manga touched since [watermark]. Boundary
/// entries (same second as watermark) are re-included since a resync is
/// idempotent but a missed chapter isn't; [sawWatermark] false means the
/// scan hit its page budget first, so the tail is unknown, not empty.
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
  // First run has no watermark to reach: one page seeds it (the caller falls
  // back to a full keep-rule pass), instead of paging a library's whole
  // backlog as if it were new.
  final pageBudget = watermark == 0 ? 1 : _maxCatchUpPages;
  for (var page = 0; page < pageBudget; page++) {
    final nodes = await fetchPage(page);
    if (nodes == null) break;
    if (nodes.isEmpty) {
      // The feed genuinely ended — nothing older remains unseen.
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

/// Fetch each manga's chapter list from the server, mirror it into drift, then
/// reconcile. Called from the bulk keep-rule change path.
///
/// The server fetch is not optional even for a manga whose chapters are already
/// mirrored: the reconciler routes purely on the stored `serverIsDownloaded`
/// flag, and that mirror goes stale between syncs. A stale-true value routes a
/// chapter straight to a device download that bypasses the server; a stale-false
/// value re-enqueues a chapter the server already holds, which drains with no
/// edge and never pulls to the device. Re-syncing first (syncChapters writes the
/// server's current isDownloaded) is what keeps both hops correct.
///
/// Mirrors [_syncAndReconcile] but also kicks the download starter so the
/// freshly-queued chapters begin transferring without waiting for the next
/// library update.
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

/// The manga-details chain, minus the screen: stored chapters from the server,
/// mirrored into drift, then reconciled. Sequential on purpose — an update can
/// touch much of a library, and this runs behind the UI.
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
      // Never reconcile on a failed fetch — evictions must not run against a
      // list the server didn't actually give us.
      allSynced = false;
      logger.w('Offline: catch-up skipped manga $mangaId: $e');
    }
  }
  return allSynced;
}

/// Like [reconcileMangaContainer], but also records server-download enqueues
/// so the queue-drain trigger knows which manga still owe a device pull.
/// Returns false on a failed enqueue (reconcileMangaCore swallows the error)
/// so the pass won't advance the watermark past an unqueued chapter.
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
            // Recorded only on success: a failed enqueue produces no queue
            // activity, so no drain edge would ever retry the waiting entry.
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
