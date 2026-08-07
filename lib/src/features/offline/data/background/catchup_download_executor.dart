// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../notifications/data/notification_state_store.dart';
import '../chapter_manifest.dart';
import '../offline_database.dart';
import '../offline_page_store.dart';
import '../offline_page_store_io.dart';
import '../offline_paths.dart';
import '../offline_types.dart';
import '../reconcile_logic.dart';
import 'background_chapter_fetch.dart';
import 'background_completion_log.dart';
import 'background_download_lock.dart';
import 'background_token_record.dart';
import 'catchup_work_spec.dart';

/// Per-run bounds under WorkManager's ~10-minute budget: stop cleanly with
/// headroom rather than get killed mid-write.
const _maxChaptersPerRun = 10;
const _runBudget = Duration(minutes: 7);

/// Download the ledger's obligations inside the WorkManager task. Returns
/// false only on transient failure (scheduler retries).
///
/// Server-client invariant holds in background too: a chapter the server has
/// not downloaded is enqueued server-side and collected a later run — the
/// device never proxies a source through the server without the server keeping
/// its copy.
Future<bool> runCatchupDownloads({
  required CatchupStateStore catchupStore,
  required NotificationWorkerConfig config,
  required BackgroundTokenRecord Function() record,
  required TokenBroker broker,
}) async {
  final spec = catchupStore.readSpec();
  if (spec == null || spec.serverId != config.serverId) return true;

  var ledger = catchupStore.readLedger(config.serverId);
  if (ledger.pendingDownloads.isEmpty && ledger.pendingServerFetch.isEmpty) {
    return true;
  }

  // Wi-Fi-only is enforced here, not in the task's constraints — tightening
  // those would silently stop the notification check on cellular.
  if (spec.wifiOnly) {
    final net = await Connectivity().checkConnectivity();
    final unmetered =
        net.contains(ConnectivityResult.wifi) ||
        net.contains(ConnectivityResult.ethernet);
    if (!unmetered) return true; // not an error — just not now
  }

  final support = await getApplicationSupportDirectory();
  final paths = OfflinePaths('${support.path}${Platform.pathSeparator}offline');
  final store = IoOfflinePageStore(paths);
  final log = BackgroundCompletionLog(
    File('${paths.baseDir}/.bg_completion.log'),
  );
  final lock = BackgroundDownloadLock(File('${paths.baseDir}/.bg_lock'));

  // The FGS may legitimately own the log right now; skip the run rather than
  // interleave writers.
  if (!await lock.acquire('wm-catchup')) return true;
  try {
    final target = BackgroundServerTarget(
      serverBase: config.endpoint.baseUrl,
      port: config.endpoint.port,
      addPort: config.endpoint.addPort,
    );
    final deadline = DateTime.now().add(_runBudget);
    var downloaded = 0;
    // Stop-after-crossing per chapter: pre-fetch sizes are unknown, so the
    // overshoot is bounded by one chapter. Usage comes from the spec snapshot
    // plus this run's own writes.
    var runBytes = 0;
    bool capBlocked() =>
        spec.storageCapEnabled &&
        spec.usedBytes + runBytes >= spec.storageCapBytes;

    final mangaIds = {
      ...ledger.pendingDownloads.values,
      ...ledger.pendingServerFetch.values,
    };
    for (final mangaId in mangaIds) {
      if (downloaded >= _maxChaptersPerRun) break;
      if (DateTime.now().isAfter(deadline)) break;
      if (await lock.yieldRequested()) break;
      final mangaSpec = spec.manga
          .where((m) => m.mangaId == mangaId)
          .firstOrNull;
      if (mangaSpec == null) {
        // Rule removed since resolution: drop the obligations.
        ledger = _dropManga(ledger, mangaId);
        await catchupStore.writeLedger(config.serverId, ledger);
        continue;
      }

      final chapters = await _fetchMangaChapters(
        target,
        record,
        broker,
        mangaId,
      );
      if (chapters == null) return false; // transient — retry next wake

      // Pinned chapters are always desired; the server rows can't know about
      // pins (device-side state), so the spec's set joins the rule's.
      final serverIds = {for (final r in chapters.rows) r.id};
      final desired = desiredChapterIds(
        chapters.rows,
        mangaSpec.keepRule,
        mangaSpec.keepUnreadCount,
      )..addAll(mangaSpec.pinnedChapterIds.intersection(serverIds));

      // Present = every truth the executor can see without drift.
      final present = <int>{
        ...mangaSpec.onDeviceChapterIds,
        ...await _loggedOrCommitted(log, store, mangaId, desired),
      };

      final serverFetch = {...ledger.pendingServerFetch};
      final retries = {...ledger.serverFetchRetries};
      final pending = {...ledger.pendingDownloads};

      for (final chapterId in desired.difference(present)) {
        if (downloaded >= _maxChaptersPerRun) break;
        if (DateTime.now().isAfter(deadline)) break;
        if (capBlocked()) break;
        if (await lock.yieldRequested()) break;
        final row = chapters.byId[chapterId];
        if (row == null) continue;

        if (!row.serverIsDownloaded) {
          // Two-hop: server first. Bounded retries; a dead source stops
          // burning the budget and surfaces via the foreground banner.
          final spent = retries[chapterId] ?? 0;
          if (spent >= 5) continue;
          final ok = await _enqueueServerDownload(target, record, chapterId);
          if (ok) {
            serverFetch[chapterId] = mangaId;
            retries[chapterId] = spent + 1;
          }
          continue;
        }

        final staged = await _downloadOneChapter(
          target: target,
          record: record,
          broker: broker,
          store: store,
          log: log,
          spec: spec,
          row: row,
          mangaId: mangaId,
        );
        if (staged > 0) {
          downloaded++;
          runBytes += staged;
          pending.remove(chapterId);
          serverFetch.remove(chapterId);
          retries.remove(chapterId);
        }
      }

      // Drop obligations that are satisfied (present) or no longer desired
      // (rule window moved on) — either way there is nothing left to do.
      pending.removeWhere(
        (c, m) => m == mangaId && (!desired.contains(c) || present.contains(c)),
      );

      ledger = ledger.copyWith(
        pendingDownloads: pending,
        pendingServerFetch: serverFetch,
        serverFetchRetries: retries,
      );
      await catchupStore.writeLedger(config.serverId, ledger);
    }
    return true;
  } finally {
    await lock.release();
  }
}

CatchupLedger _dropManga(CatchupLedger ledger, int mangaId) => ledger.copyWith(
  pendingDownloads: {
    for (final e in ledger.pendingDownloads.entries)
      if (e.value != mangaId) e.key: e.value,
  },
  pendingServerFetch: {
    for (final e in ledger.pendingServerFetch.entries)
      if (e.value != mangaId) e.key: e.value,
  },
);

/// Chapters already recorded in the un-replayed log, or already committed on
/// disk — work the spec's snapshot can't know about yet.
///
/// Deliberately NOT "staging looks complete". Staging fills before the adoption
/// record is written, so a worker killed in that window would leave a directory
/// that satisfies the obligation while nothing durable claims it: the ledger
/// entry would be dropped here, and replay — finding files with no row and no
/// record — would delete them. The chapter would simply vanish from the queue.
/// A committed directory is the safe equivalent, because only an adoption that
/// already replayed could have produced one.
Future<Set<int>> _loggedOrCommitted(
  BackgroundCompletionLog log,
  IoOfflinePageStore store,
  int mangaId,
  Set<int> candidates,
) async {
  final present = <int>{};
  for (final e in await log.parse()) {
    if (e is AdoptChapterEntry && e.mangaId == mangaId)
      present.add(e.chapterId);
    if (e is ChapterEntry && e.status == 'downloaded') present.add(e.chapterId);
  }
  for (final chapterId in candidates) {
    if (present.contains(chapterId)) continue;
    final committed = await store.inspectCommitted(mangaId, chapterId);
    if (committed.state == ChapterDirState.complete ||
        committed.state == ChapterDirState.legacy) {
      present.add(chapterId);
    }
  }
  return present;
}

class _MangaChapters {
  _MangaChapters(this.rows) : byId = {for (final r in rows) r.id: r};
  final List<OfflineChapter> rows;
  final Map<int, OfflineChapter> byId;
}

/// The manga's live chapter list, shaped as [OfflineChapter] rows so the pure
/// keep-rule math runs on it unchanged. Null when the server was unreachable.
Future<_MangaChapters?> _fetchMangaChapters(
  BackgroundServerTarget target,
  BackgroundTokenRecord Function() record,
  TokenBroker broker,
  int mangaId,
) async {
  const query =
      'query MangaChapters(\$id: Int!){ chapters(condition:{mangaId: \$id}, order:[{by: SOURCE_ORDER, byType: ASC}]){ nodes { id name sourceOrder chapterNumber isRead isBookmarked isDownloaded pageCount } } }';
  Future<Object?> post(String? accessToken) => postBackgroundGraphql(
    target: target,
    record: record(),
    query: query,
    variables: {'id': mangaId},
    accessToken: accessToken,
  );
  var result = await post(null);
  if (result == gqlAuthError && record().authType == 'uiLogin') {
    final newAccess = await broker.resolveAfter401(record().accessToken ?? '');
    if (newAccess != null) result = await post(newAccess);
  }
  if (result == gqlNetworkError) return null;
  if (result is! Map<String, Object?>) return _MangaChapters(const []);
  final nodes =
      ((result['chapters'] as Map<String, Object?>?)?['nodes'] as List? ??
      const []);
  final now = DateTime.now();
  return _MangaChapters([
    for (final n in nodes.cast<Map<String, Object?>>())
      OfflineChapter(
        id: (n['id'] as num).toInt(),
        mangaId: mangaId,
        name: n['name'] as String? ?? '',
        chapterIndex: (n['sourceOrder'] as num?)?.toInt() ?? 0,
        isRead: n['isRead'] as bool? ?? false,
        lastPageRead: 0,
        isBookmarked: n['isBookmarked'] as bool? ?? false,
        serverIsDownloaded: n['isDownloaded'] as bool? ?? false,
        deviceState: OfflineDeviceState.none,
        pageCount: (n['pageCount'] as num?)?.toInt() ?? 0,
        bytes: 0,
        pinned: false,
        downloadedAt: null,
        progressDirty: false,
        bookmarkDirty: false,
        readStateDirty: false,
        syncedIsRead: n['isRead'] as bool? ?? false,
        updatedAt: now,
        downloadGeneration: 0,
      ),
  ]);
}

Future<bool> _enqueueServerDownload(
  BackgroundServerTarget target,
  BackgroundTokenRecord Function() record,
  int chapterId,
) async {
  const query =
      'mutation EnqueueDownloads(\$input: EnqueueChapterDownloadsInput!){ enqueueChapterDownloads(input: \$input){ __typename } }';
  final result = await postBackgroundGraphql(
    target: target,
    record: record(),
    query: query,
    variables: {
      'input': {
        'ids': [chapterId],
      },
    },
  );
  return result is Map<String, Object?>;
}

/// Download one chapter into staging, returning the bytes staged (0 when it
/// didn't finish).
///
/// This worker never publishes a chapter — it has no drift access, so it cannot
/// check the row the way a commit must. It fills staging and leaves an adoption
/// record; the next launch commits it on the main isolate. Timing is unchanged
/// for the user: adoption already happened at replay.
Future<int> _downloadOneChapter({
  required BackgroundServerTarget target,
  required BackgroundTokenRecord Function() record,
  required TokenBroker broker,
  required IoOfflinePageStore store,
  required BackgroundCompletionLog log,
  required CatchupWorkSpec spec,
  required OfflineChapter row,
  required int mangaId,
}) async {
  final urls = await resolveChapterPageUrls(
    target: target,
    record: record,
    broker: broker,
    chapterId: row.id,
  );
  if (urls == null || urls.isEmpty) return 0;

  final indices = [for (var i = 0; i < urls.length; i++) i];
  // Generation 0: the row doesn't exist yet, so it will be created at
  // generation 0 by the adoption pass. A chapter drift already knows about is
  // never routed here — it is `present` and skipped.
  await store.deleteStaging(mangaId, row.id);
  await store.beginChapter(
    mangaId,
    row.id,
    ChapterManifest(generation: 0, indices: indices),
  );

  final engine = buildBackgroundEngine(
    store: store,
    target: target,
    record: record,
    broker: broker,
  );
  final outcome = await engine.download(
    mangaId: mangaId,
    chapterId: row.id,
    pages: [for (var i = 0; i < urls.length; i++) (index: i, url: urls[i])],
    isCancelled: () => false,
    onPageStored: (_, __, ___) async {},
  );
  if (!outcome.succeeded) return 0;

  final bytes = outcome.storedPages.values.fold<int>(0, (s, p) => s + p.bytes);
  await log.appendAdopt(
    AdoptChapterEntry(
      chapterId: row.id,
      mangaId: mangaId,
      serverId: spec.serverId,
      name: row.name,
      chapterIndex: row.chapterIndex,
      chapterNumber: row.chapterNumber ?? -1,
      pageCount: urls.length,
      bytes: bytes,
      isRead: row.isRead,
    ),
  );
  return bytes;
}
