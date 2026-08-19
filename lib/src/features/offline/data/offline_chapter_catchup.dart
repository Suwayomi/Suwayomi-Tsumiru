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
import '../../manga_book/data/downloads/downloads_repository.dart';
import '../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../manga_book/data/updates/updates_repository.dart';
import '../../manga_book/presentation/downloads/controller/downloads_controller.dart';
import '../../settings/presentation/downloads/data/delete_chapters_settings_repository.dart';
import 'background/background_download_controller_shim.dart';
import 'background/background_download_lock.dart';
import 'background/catchup_spec_writer.dart';
import 'background/catchup_work_spec.dart';
import 'offline_background_downloads.dart';
import 'offline_database.dart';
import 'offline_download_providers.dart';
import 'offline_repository.dart';
import 'offline_types.dart';

/// Closes the #310 gap: a library update told the SERVER to find new chapters,
/// but nothing on the client synced or downloaded them for keep-rule manga —
/// the full fetch→mirror→reconcile chain only ran on a manga-details visit.

/// Feed pages scanned per pass. Running out of budget before reaching the
/// watermark falls back to a full keep-rule pass, so the cap trades feed
/// queries for chapter-list fetches rather than dropping anything.
const _maxCatchUpPages = 3;

bool _running = false;

/// Set by the [downloadsMapProvider] drain listener when a drain event fires
/// while a catch-up pass holds [_running]. Rather than dropping the event, we
/// record it here and replay [_pullAwaiting] at the tail of the current pass so
/// chapters that became serverIsDownloaded during the pass are not stranded
/// until the next update cycle.
bool _drainMissedDuringPass = false;

/// Manga whose reconcile had to ask the SERVER to download chapters first.
/// Their device pull can only happen after those finish — see
/// [pullAfterServerDownloads].
final Set<int> _awaitingServerDownloads = {};

/// Resets all module-private state. The three globals above persist across
/// `test()` cases in the same file (one isolate per file), so every test
/// exercising this module must call this in `setUp`.
@visibleForTesting
void resetChapterCatchUpStateForTest() {
  _running = false;
  _drainMissedDuringPass = false;
  _awaitingServerDownloads.clear();
}

@visibleForTesting
void seedAwaitingServerDownloadsForTest(Iterable<int> mangaIds) {
  _awaitingServerDownloads
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
  // Restore the second-hop obligations — the watermark has already moved past
  // these manga, so losing the set to a restart would strand their pulls.
  _awaitingServerDownloads.addAll(
    container
            .read(sharedPreferencesProvider)
            .getStringList(DBKeys.offlineCatchUpAwaitingPull.name)
            ?.map(int.tryParse)
            .whereType<int>() ??
        const [],
  );
  // Adopt the background worker's second-hop obligations: chapters it queued
  // server-side get pulled by the foreground machinery now instead of waiting
  // for the next background wake. Exhausted retries hand off the same way —
  // foreground reconcile owns surfacing stuck downloads.
  unawaited(_adoptWorkerObligations(container));
  // A finished server update run is the moment new chapters exist to pull.
  container.listen(updateRunningSocketProvider, (previous, next) {
    final wasRunning = previous?.value ?? false;
    final isRunning = next.value ?? wasRunning;
    if (wasRunning && !isRunning) {
      unawaited(runKeepRuleCatchUp(container));
    }
  });
  // The server's download queue draining is the moment chapters queued by a
  // catch-up reconcile become pullable to the device.
  container.listen(downloadsMapProvider, (previous, next) {
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
  // Catch anything the server found while the app was closed.
  unawaited(runKeepRuleCatchUp(container));
}

/// Read-modify-write on the worker's ledger, so it runs under the download
/// lock (a live worker run means skip — next launch retries) and against a
/// freshly reloaded prefs cache, never this isolate's stale snapshot.
Future<void> _adoptWorkerObligations(ProviderContainer container) async {
  try {
    final catalogServerId = container
        .read(sharedPreferencesProvider)
        .getString(DBKeys.offlineCatalogServerId.name);
    if (catalogServerId == null) return;
    final catchupStore = await CatchupStateStore.open();
    final ledger = catchupStore.readLedger(catalogServerId);
    if (ledger.pendingServerFetch.isEmpty) return;

    final paths = container.read(offlinePathsProvider);
    final lock = BackgroundDownloadLock(File('${paths.baseDir}/.bg_lock'));
    if (!await lock.acquire('handoff')) return;
    try {
      // Re-open INSIDE the lock: open() reloads the prefs cache, so the read
      // below cannot predate a worker write that slipped in before acquire.
      final lockedStore = await CatchupStateStore.open();
      final fresh = lockedStore.readLedger(catalogServerId);
      if (fresh.pendingServerFetch.isEmpty) return;
      _awaitingServerDownloads.addAll(fresh.pendingServerFetch.values);
      await _persistAwaiting(container);
      await lockedStore.writeLedger(
        catalogServerId,
        fresh.copyWith(
          pendingServerFetch: const {},
          serverFetchRetries: const {},
        ),
      );
    } finally {
      await lock.release();
    }
  } catch (e) {
    logger.w('Offline: adopting worker obligations failed: $e');
  }
}

/// Single-flight: an update trigger landing mid-pass is dropped, since its
/// chapters are newer than the watermark and will be picked up by the next
/// pass. A server-download drain event landing mid-pass is instead deferred
/// via [_drainMissedDuringPass] and replayed at the tail of the current pass.
Future<void> runKeepRuleCatchUp(ProviderContainer container) async {
  if (_running) return;
  if (!container.read(offlineActiveProvider)) return;
  _running = true;
  try {
    final keepRuleManga = {
      for (final m
          in await container.read(offlineDatabaseProvider).libraryManga())
        if (m.keepRule != OfflineKeepRule.off) m.id,
    };
    if (keepRuleManga.isEmpty) {
      if (_drainMissedDuringPass) {
        _drainMissedDuringPass = false;
        await _pullAwaiting(container);
      }
      return;
    }

    final prefs = container.read(sharedPreferencesProvider);
    final watermark = prefs.getInt(DBKeys.offlineCatchUpWatermark.name) ?? 0;

    final scan = await touchedSinceWatermark(
      fetchPage: (pageNo) async {
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
    final feedTouched = scan.sawWatermark ? scan.touched : keepRuleManga;
    // Also include manga still awaiting a server-side download. Their
    // serverIsDownloaded flag can flip without generating a new feed entry
    // (e.g. a manual re-download via the WebUI), so the watermark scan would
    // miss them — always give them a fresh sync attempt.
    final touched = {
      ...feedTouched,
      ..._awaitingServerDownloads.where(keepRuleManga.contains),
    };
    final allSynced = await _syncAndReconcile(container, touched);

    // Only a fully-processed pass may advance the watermark — a skipped manga
    // must stay newer than it so the next pass retries. syncChapters is
    // idempotent, so re-processing the rest is just cheap.
    if (allSynced && scan.newestFetchedAt > watermark) {
      await prefs.setInt(
        DBKeys.offlineCatchUpWatermark.name,
        scan.newestFetchedAt,
      );
    }
    if (touched.isNotEmpty) {
      await container.read(downloadStarterProvider)();
    }
    // Manga still waiting on server-side downloads get retried here too — the
    // queue-drain edge alone can be missed when downloads finish faster than
    // the subscription reports them.
    await _pullAwaiting(container);
    // If a drain event arrived while this pass was in flight, the listener
    // deferred it instead of dropping it. Re-run the pull now so chapters that
    // became serverIsDownloaded during the pass are not stranded until the next
    // update cycle.
    if (_drainMissedDuringPass) {
      _drainMissedDuringPass = false;
      await _pullAwaiting(container);
    }
    // Freshest device-state snapshot for the background worker.
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
Future<void> pullAfterServerDownloads(ProviderContainer container) async {
  if (_running) return;
  _running = true;
  try {
    await _pullAwaiting(container);
    if (_drainMissedDuringPass) {
      _drainMissedDuringPass = false;
      await _pullAwaiting(container);
    }
  } finally {
    _running = false;
  }
}

Future<void> _pullAwaiting(ProviderContainer container) async {
  if (_awaitingServerDownloads.isEmpty) return;
  if (!container.read(offlineActiveProvider)) return;
  // One obligation at a time, persisted after each: a crash mid-loop keeps
  // the unprocessed rest, and a batch clear would lose them.
  for (final mangaId in {..._awaitingServerDownloads}) {
    _awaitingServerDownloads.remove(mangaId);
    // The reconcile may re-add this manga (a NEW server enqueue) — that is a
    // fresh obligation, not the one being consumed, so it must survive.
    final ok = await _syncAndReconcile(container, {mangaId});
    if (!ok) _awaitingServerDownloads.add(mangaId);
    await _persistAwaiting(container);
  }
  await container.read(downloadStarterProvider)();
}

Future<void> _persistAwaiting(ProviderContainer container) =>
    container.read(sharedPreferencesProvider).setStringList(
      DBKeys.offlineCatchUpAwaitingPull.name,
      [for (final id in _awaitingServerDownloads) '$id'],
    );

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

/// The manga-details chain, minus the screen: stored chapters from the server,
/// mirrored into drift, then reconciled. Sequential on purpose — an update can
/// touch much of a library, and this runs behind the UI.
Future<bool> _syncAndReconcile(
  ProviderContainer container,
  Set<int> mangaIds,
) async {
  var allSynced = true;
  for (final mangaId in mangaIds) {
    try {
      final chapters = await container
          .read(mangaBookRepositoryProvider)
          .getStoredChapterList(mangaId);
      final sync = container.read(offlineSyncProvider);
      if (chapters == null || sync == null) {
        allSynced = false;
        continue;
      }
      await sync.syncChapters(chapters);
      if (!await _reconcileTracked(container, mangaId)) allSynced = false;
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
Future<bool> _reconcileTracked(ProviderContainer container, int mangaId) async {
  final manager = container.read(offlineDownloadManagerProvider);
  final coordinator = container.read(offlineDownloadCoordinatorProvider);
  if (manager == null || coordinator == null) return false;
  var enqueueFailed = false;
  await reconcileMangaCore(
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
    enqueueServerDownload: (ids) async {
      try {
        await container
            .read(downloadsRepositoryProvider)
            .addChaptersBatchToDownloadQueue(ids);
        // Recorded only on success: a failed enqueue produces no queue
        // activity, so no drain edge would ever retry the waiting entry.
        _awaitingServerDownloads.add(mangaId);
      } catch (_) {
        enqueueFailed = true;
        rethrow;
      }
    },
    removeFromWorker: (id, gen) async {
      final ctrl = container.read(backgroundDownloadControllerProvider);
      await ctrl.onRemoved(id);
      await ctrl.recordChapterDeleted(id, gen);
    },
  );
  await _persistAwaiting(container);
  return !enqueueFailed;
}
