// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../utils/crash/diagnostics.dart';
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

/// Attempts a single chapter gets across runs before its obligation is dropped.
/// Without this the ledger never converges: a chapter the server cannot serve
/// stays pending and is retried on every scheduled wake, forever.
const _maxChapterAttempts = 5;

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
  // spec.serverId is the offline catalog's server-instance id (what
  // writeCatchupWorkSpec stamps it with) — NOT config.serverId, which is a
  // "url|port" string scoping the unrelated notification cursor. Comparing
  // against the wrong one meant this guard could never pass.
  if (spec == null || spec.serverId != catchupStore.catalogServerId) {
    recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] offline-catchup: '
      'run-skipped reason=no-spec\n',
    );
    return true;
  }

  var ledger = catchupStore.readLedger(config.serverId);

  // Compute backfill needs BEFORE the early-exit: an empty ledger is not
  // necessarily empty work — manga in the spec that have never had a full
  // chapter-list pass need one regardless of whether there are ledger
  // obligations (the ledger starts empty on every fresh spec or server switch).
  final needsBackfill = spec.keepRuleMangaIds.difference(
    ledger.backfilledMangaIds,
  );
  recordDiagnostic(
    '[${DateTime.now().toIso8601String()}] offline-catchup: run-started '
    'pendingDownloads=${ledger.pendingDownloads.length} '
    'pendingServerFetch=${ledger.pendingServerFetch.length} '
    'needsBackfill=${needsBackfill.length}\n',
  );
  if (ledger.pendingDownloads.isEmpty &&
      ledger.pendingServerFetch.isEmpty &&
      needsBackfill.isEmpty) {
    return true;
  }

  // Wi-Fi-only is enforced here, not in the task's constraints — tightening
  // those would silently stop the notification check on cellular.
  if (spec.wifiOnly) {
    final net = await Connectivity().checkConnectivity();
    final unmetered =
        net.contains(ConnectivityResult.wifi) ||
        net.contains(ConnectivityResult.ethernet);
    if (!unmetered) {
      recordDiagnostic(
        '[${DateTime.now().toIso8601String()}] offline-catchup: '
        'run-skipped reason=wifi-required\n',
      );
      return true; // not an error — just not now
    }
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
  if (!await lock.acquire('wm-catchup')) {
    recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] offline-catchup: '
      'lock-held-skip\n',
    );
    return true;
  }
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

    // Read once for the whole run. Safe not because the log is frozen — this
    // executor appends to it below — but because each manga is visited exactly
    // once and the only entries written meanwhile belong to the manga being
    // processed, which the filter below drops anyway. A retry loop or a second
    // pass would break that.
    final logEntries = await log.parse();
    // needsBackfill was computed before the early-exit check so it is already
    // available here; the set is the same because backfilledMangaIds only grows
    // during the run and we haven't touched the ledger yet at this point.
    if (needsBackfill.isNotEmpty) {
      recordDiagnostic(
        '[${DateTime.now().toIso8601String()}] offline-catchup: '
        'backfilling-manga ids=${needsBackfill.join(',')}\n',
      );
    }
    final mangaIds = {
      ...needsBackfill,
      ...ledger.pendingDownloads.values,
      ...ledger.pendingServerFetch.values,
    };
    outer:
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

      final serverFetch = {...ledger.pendingServerFetch};
      final retries = {...ledger.serverFetchRetries};
      final dlRetries = {...ledger.downloadRetries};
      final pending = {...ledger.pendingDownloads};

      // A chapter that has spent its attempt budget on either hop is already a
      // permanent dead end this run onward (both hops below `continue` once
      // their own counter maxes out, and a counter only ever clears when the
      // chapter leaves `desired` — which it never does on its own). Excluding
      // it from the candidate pool here, rather than after, stops it wasting
      // one of a `nUnread` rule's N slots forever: without this, the
      // (N+1)th unread chapter never gets a turn, and "keep N downloaded"
      // silently plateaus at N-1.
      final exhausted = <int>{};
      for (final r in chapters.rows) {
        final serverFetchSpent = retries[r.id] ?? 0;
        final downloadSpent = dlRetries[r.id] ?? 0;
        if (serverFetchSpent < _maxChapterAttempts &&
            downloadSpent < _maxChapterAttempts) {
          continue;
        }
        exhausted.add(r.id);
        recordDiagnostic(
          '[${DateTime.now().toIso8601String()}] offline-catchup: '
          'giving-up-on-chapter mangaId=$mangaId chapterId=${r.id} '
          'name="${r.name}" index=${r.chapterIndex} '
          'serverFetchAttempts=$serverFetchSpent/$_maxChapterAttempts '
          'downloadAttempts=$downloadSpent/$_maxChapterAttempts '
          'serverIsDownloaded=${r.serverIsDownloaded} '
          '— excluded from this manga\'s keep-rule slots from now on\n',
        );
      }
      final desired = desiredChapterIds(
        [for (final r in chapters.rows) if (!exhausted.contains(r.id)) r],
        mangaSpec.keepRule,
        mangaSpec.keepUnreadCount,
      )..addAll(mangaSpec.pinnedChapterIds.intersection(serverIds));

      // Present = every truth the executor can see without drift.
      final present = <int>{
        ...mangaSpec.onDeviceChapterIds,
        ...await _loggedOrCommitted(logEntries, store, mangaId, desired),
      };

      for (final chapterId in desired.difference(present)) {
        if (downloaded >= _maxChaptersPerRun) break;
        if (DateTime.now().isAfter(deadline)) break;
        if (capBlocked()) break;
        if (await lock.yieldRequested()) break;
        final row = chapters.byId[chapterId];
        if (row == null) continue;

        // A budget per hop, spent only on that hop's own failures. Sharing one
        // meant a slow source could exhaust a chapter before the device had
        // tried at all, and a chapter neither hop can produce is otherwise
        // retried on every wake for the life of the install.
        //
        // Counters outlive the obligation they gave up on: `desired` is rebuilt
        // from the spec each run, so a cleared counter just starts the attempts
        // over. Success clears them; so does the chapter leaving the window.
        if (!row.serverIsDownloaded) {
          final spent = retries[chapterId] ?? 0;
          if (spent >= _maxChapterAttempts) {
            // Stop asking, but keep the obligation: it is what tells the ledger
            // which manga this chapter belongs to, so the window cleanup below
            // can drop the counter with it once the chapter is no longer
            // wanted. Skipping costs nothing — the gate is ahead of any I/O.
            serverFetch.remove(chapterId);
            continue;
          }
          // Two-hop: ask the server to fetch it from the source first. A failed
          // ask is the server not being there, which costs nothing.
          final ok = await _enqueueServerDownload(
            target,
            record,
            broker,
            chapterId,
          );
          // A trail of every attempt, not just the final give-up — so a run
          // that never reaches the cap is still visible, and a failed
          // enqueue request (server unreachable) is distinguishable from one
          // that succeeded but the source never actually produced the
          // chapter (serverIsDownloaded staying false on a later run).
          recordDiagnostic(
            '[${DateTime.now().toIso8601String()}] offline-catchup: '
            'asking-server-to-fetch mangaId=$mangaId chapterId=$chapterId '
            'name="${row.name}" index=${row.chapterIndex} '
            'enqueueOk=$ok attempt=${spent + 1}/$_maxChapterAttempts\n',
          );
          if (ok) {
            serverFetch[chapterId] = mangaId;
            retries[chapterId] = spent + 1;
          }
          continue;
        }

        // On the server now, so this is a fresh job with its own budget however
        // many runs the fetch above took.
        serverFetch.remove(chapterId);
        final dlSpent = dlRetries[chapterId] ?? 0;
        if (dlSpent >= _maxChapterAttempts) continue;

        // Re-check connectivity before each chapter's page downloads — the
        // one-time gate at run start can't catch a WiFi drop mid-run.
        if (spec.wifiOnly) {
          final net = await Connectivity().checkConnectivity();
          if (!net.contains(ConnectivityResult.wifi) &&
              !net.contains(ConnectivityResult.ethernet)) {
            recordDiagnostic(
              '[${DateTime.now().toIso8601String()}] offline-catchup: '
              'run-paused reason=wifi-lost mid-run\n',
            );
            break outer;
          }
        }

        final attempt = await _downloadOneChapter(
          target: target,
          record: record,
          broker: broker,
          store: store,
          log: log,
          spec: spec,
          row: row,
          mangaId: mangaId,
          generation: mangaSpec.generationOf(chapterId),
        );
        if (attempt.bytes > 0) {
          downloaded++;
          runBytes += attempt.bytes;
          pending.remove(chapterId);
          serverFetch.remove(chapterId);
          retries.remove(chapterId);
          dlRetries.remove(chapterId);
          recordDiagnostic(
            '[${DateTime.now().toIso8601String()}] offline-catchup: '
            'downloaded-chapter mangaId=$mangaId chapterId=$chapterId '
            'bytes=${attempt.bytes}\n',
          );
        } else if (!attempt.transient) {
          dlRetries[chapterId] = dlSpent + 1;
        }
      }

      // Drop obligations that are satisfied (present) or no longer desired
      // (rule window moved on) — either way there is nothing left to do. The
      // attempt counters go with them: they exist to stop a chapter being
      // retried while it is still wanted, so one left behind would meet a
      // re-added chapter with an already-spent budget.
      //
      // Scans BOTH maps, not just `pending`: a chapter can be exhausted (and
      // now excluded from `desired` above) while it only ever reached
      // `pendingServerFetch` — never promoted to `pendingDownloads`. Dropping
      // it from `pending` alone left it in `serverFetch` forever, which kept
      // its manga in the `mangaIds` set at the top of this run and re-issued
      // a real chapter-list fetch for it on every wake indefinitely, even
      // though nothing was ever going to download.
      //
      // `exhausted` is deliberately excluded from the "no longer desired"
      // half of this condition: it is ALSO why those chapters are missing
      // from `desired` (see above), and wiping their counters here would
      // reset them to 0 next run — un-exhausting a chapter right back into
      // fresh attempts and undoing the whole point of excluding it. A
      // chapter drops out of `desired` for two different reasons and only
      // one of them should forgive its spent budget.
      final done = {
        for (final e in pending.entries)
          if (e.value == mangaId &&
              ((!desired.contains(e.key) && !exhausted.contains(e.key)) ||
                  present.contains(e.key)))
            e.key,
        for (final e in serverFetch.entries)
          if (e.value == mangaId &&
              ((!desired.contains(e.key) && !exhausted.contains(e.key)) ||
                  present.contains(e.key)))
            e.key,
      };
      for (final c in done) {
        pending.remove(c);
        serverFetch.remove(c);
        retries.remove(c);
        dlRetries.remove(c);
      }

      ledger = ledger.copyWith(
        pendingDownloads: pending,
        pendingServerFetch: serverFetch,
        serverFetchRetries: retries,
        downloadRetries: dlRetries,
        // The chapter-list fetch above already ran, whether or not this
        // manga was one that needed it — recording it here (not just inside
        // the needsBackfill branch) keeps the set accurate for every manga
        // this run actually looked at.
        backfilledMangaIds: {...ledger.backfilledMangaIds, mangaId},
      );
      await catchupStore.writeLedger(config.serverId, ledger);
    }
    recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] offline-catchup: '
      'run-finished downloaded=$downloaded bytes=$runBytes\n',
    );
    return true;
  } finally {
    await lock.release();
  }
}

CatchupLedger _dropManga(CatchupLedger ledger, int mangaId) {
  final gone = {
    for (final e in ledger.pendingDownloads.entries)
      if (e.value == mangaId) e.key,
    for (final e in ledger.pendingServerFetch.entries)
      if (e.value == mangaId) e.key,
  };
  Map<int, int> without(Map<int, int> m) => {
    for (final e in m.entries)
      if (!gone.contains(e.key)) e.key: e.value,
  };
  return ledger.copyWith(
    pendingDownloads: without(ledger.pendingDownloads),
    pendingServerFetch: without(ledger.pendingServerFetch),
    // The rule is gone, so the attempts spent under it mean nothing — leaving
    // them would meet the manga with a spent budget if it came back.
    serverFetchRetries: without(ledger.serverFetchRetries),
    downloadRetries: without(ledger.downloadRetries),
    // Same reasoning: a manga that comes back under the rule again is a fresh
    // backlog as far as this executor knows, not one it already visited.
    backfilledMangaIds: {...ledger.backfilledMangaIds}..remove(mangaId),
  );
}

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
  List<LogEntry> logEntries,
  IoOfflinePageStore store,
  int mangaId,
  Set<int> candidates,
) async {
  final present = <int>{};
  for (final e in logEntries) {
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
        readStateManual: false,
        syncedIsRead: n['isRead'] as bool? ?? false,
        updatedAt: now,
        downloadGeneration: 0,
        serverFetchAttempts: 0,
      ),
  ]);
}

Future<bool> _enqueueServerDownload(
  BackgroundServerTarget target,
  BackgroundTokenRecord Function() record,
  TokenBroker broker,
  int chapterId,
) async {
  const query =
      'mutation EnqueueDownloads(\$input: EnqueueChapterDownloadsInput!){ enqueueChapterDownloads(input: \$input){ __typename } }';
  Future<Object?> post(String? accessToken) => postBackgroundGraphql(
    target: target,
    record: record(),
    query: query,
    variables: {
      'input': {
        'ids': [chapterId],
      },
    },
    accessToken: accessToken,
  );
  // Without this retry, a uiLogin access token that expired between wakes
  // (the wake interval is 1-6h, far longer than a typical token lifetime)
  // makes this call 401 and give up every single run — the server never
  // actually gets asked to fetch the chapter from source in the background,
  // no matter how many attempts the ledger counts. `_fetchMangaChapters`
  // above already refreshed the token this run if it was stale, but that
  // refresh only persists to the store (via the broker), not back into
  // `record()` — so this call still needs its own retry, same as that one.
  var result = await post(null);
  if (result == gqlAuthError && record().authType == 'uiLogin') {
    final newAccess = await broker.resolveAfter401(record().accessToken ?? '');
    if (newAccess != null) result = await post(newAccess);
  }
  return result is Map<String, Object?>;
}

/// Download one chapter into staging, returning the bytes staged (0 when it
/// didn't finish).
///
/// This worker never publishes a chapter — it has no drift access, so it cannot
/// check the row the way a commit must. It fills staging and leaves an adoption
/// record; the next launch commits it on the main isolate. Timing is unchanged
/// for the user: adoption already happened at replay.
/// Whether an attempt failed because the chapter cannot be served, or merely
/// because the server was not there at the time. Only the first is worth
/// spending an attempt on — an outage would otherwise abandon the chapter for
/// good after a few nights.
typedef ChapterAttempt = ({int bytes, bool transient});

Future<ChapterAttempt> _downloadOneChapter({
  required BackgroundServerTarget target,
  required BackgroundTokenRecord Function() record,
  required TokenBroker broker,
  required IoOfflinePageStore store,
  required BackgroundCompletionLog log,
  required CatchupWorkSpec spec,
  required OfflineChapter row,
  required int mangaId,
  required int generation,
}) async {
  final urls = await resolveChapterPageUrls(
    target: target,
    record: record,
    broker: broker,
    chapterId: row.id,
  );
  // null: server unreachable. empty: it answered, and has no pages for this
  // chapter.
  if (urls == null) return (bytes: 0, transient: true);
  if (urls.isEmpty) return (bytes: 0, transient: false);

  final indices = [for (var i = 0; i < urls.length; i++) i];
  // The generation comes from the spec, not a hardcoded 0: a chapter that was
  // deleted once and re-queued keeps a bumped generation on its row, and
  // staging stamped 0 would be rejected at launch — after this run had already
  // struck the obligation off the ledger. A chapter drift has never seen has
  // no entry, so it gets 0, matching the row adoption creates.
  //
  // Reuse staging that matches, the way the foreground downloaders do. These
  // runs are cut short constantly — the WorkManager budget, a dropped
  // connection, a yield to the foreground service — and a big chapter that
  // restarted from page zero every time might never finish at all.
  final existing = await store.readManifest(mangaId, row.id);
  var staged = const <int>{};
  if (existing != null &&
      existing.generation == generation &&
      existing.coversSameIndices(indices)) {
    staged = await store.stagedPageIndices(mangaId, row.id);
  } else {
    await store.deleteStaging(mangaId, row.id);
    await store.beginChapter(
      mangaId,
      row.id,
      ChapterManifest(generation: generation, indices: indices),
    );
  }

  final engine = buildBackgroundEngine(
    store: store,
    target: target,
    record: record,
    broker: broker,
  );
  final outcome = await engine.download(
    mangaId: mangaId,
    chapterId: row.id,
    pages: [
      for (var i = 0; i < urls.length; i++)
        if (!staged.contains(i)) (index: i, url: urls[i]),
    ],
    isCancelled: () => false,
    onPageStored: (_, __, ___) async {},
  );
  if (!outcome.succeeded) {
    return (bytes: 0, transient: outcome.offline || outcome.authFailed);
  }

  // Measured off staging rather than this run's writes: a resumed chapter
  // fetched only what was missing, and the ledger's cap accounting wants the
  // whole chapter.
  final bytes = await store.stagedBytes(mangaId, row.id);
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
  return (bytes: bytes, transient: false);
}
