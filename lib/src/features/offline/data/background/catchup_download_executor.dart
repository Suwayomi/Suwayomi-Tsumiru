// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../../utils/crash/diagnostics.dart';
import '../../../account/data/account_permission.dart';
import '../../../notifications/data/background/notification_background_client.dart'
    show NotificationEndpoint;
import '../../../notifications/data/notification_state_store.dart';
import '../chapter_manifest.dart';
import '../offline_database.dart';
import '../offline_page_store.dart';
import '../offline_page_store_io.dart';
import '../offline_paths.dart';
import '../reconcile_logic.dart';
import 'background_chapter_fetch.dart';
import 'background_completion_log.dart';
import 'background_download_lock.dart';
import 'background_schedule.dart';
import 'background_token_record.dart';
import 'catchup_work_spec.dart';
import 'queued_download_runner.dart';

// Bound each run below WorkManager's time budget with headroom for cleanup.
const _maxChaptersPerRun = 10;
const _runBudget = Duration(minutes: 7);


/// False requests a scheduler retry for transient failure.
/// Missing server copies are fetched server-side first, then pulled on a later run.
Future<bool> runCatchupDownloads({
  required CatchupStateStore catchupStore,
  required NotificationWorkerConfig config,

  /// Defaults to [config] endpoint when omitted.
  NotificationEndpoint? endpoint,
  required BackgroundTokenRecord Function() record,
  required TokenBroker broker,
}) async {
  var spec = catchupStore.readSpec();
  // spec.serverId is the catalog instance id; config.serverId scopes a separate URL/port cursor.
  if (spec == null || spec.serverId != catchupStore.catalogServerId) {
    recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] offline-catchup: '
      'run-skipped reason=no-spec\n',
    );
    return true;
  }

  var ledger = catchupStore.readLedger(spec.serverId);

  // An empty ledger still needs chapter-list backfill for manga absent from prior full passes.
  var needsBackfill = spec.keepRuleMangaIds.difference(
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
      needsBackfill.isEmpty &&
      spec.queuedChapters.isEmpty) {
    return true;
  }

  // Scheduler Wi-Fi constraints would also block notification checks on cellular.
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
  final paths = OfflinePaths(
    spec.storagePath('${support.path}${Platform.pathSeparator}offline'),
  );
  final store = IoOfflinePageStore(paths);
  final log = BackgroundCompletionLog(
    File('${paths.baseDir}/.bg_completion.log'),
  );
  final lock = BackgroundDownloadLock(File('${paths.baseDir}/.bg_lock'));

  // Do not interleave log writes with the foreground-service worker.
  if (!await lock.acquire('wm-catchup')) {
    recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] offline-catchup: '
      'lock-held-skip\n',
    );
    return true;
  }
  var cancelled = false;
  Future<void>? controlCheck;
  Timer? controlTimer;
  DateTime? lastControlRefresh;
  final client = http.Client();
  final deadline = DateTime.now().add(_runBudget);
  Future<void> inspectControls() async {
    if (cancelled) return;
    try {
      final now = DateTime.now();
      if (now.isAfter(deadline) || await lock.yieldRequested()) {
        cancelled = true;
      }
      if (!cancelled &&
          (lastControlRefresh == null ||
              now.difference(lastControlRefresh!) >=
                  const Duration(seconds: 2))) {
        lastControlRefresh = now;
        await catchupStore.reload();
        final latest = catchupStore.readSpec();
        if (catchupStore.paused ||
            catchupStore.downloadPermissionPaused(spec!.serverId) ||
            !catchupStore.matchesIdentity(config) ||
            latest == null ||
            latest.serverId != spec.serverId ||
            latest.accountScoped != spec.accountScoped ||
            latest.nonAccountScoped != spec.nonAccountScoped) {
          cancelled = true;
        }
        if (!cancelled && latest!.wifiOnly) {
          final net = await Connectivity().checkConnectivity();
          if (!net.contains(ConnectivityResult.wifi) &&
              !net.contains(ConnectivityResult.ethernet)) {
            cancelled = true;
          }
        }
      }
      if (cancelled) client.close();
    } catch (_) {
      cancelled = true;
      client.close();
    }
  }

  Future<void> checkControls() => controlCheck ??= inspectControls()
      .whenComplete(() => controlCheck = null);
  Future<bool> recordDenial() async {
    if (cancelled) return false;
    return catchupStore.recordDownloadPermission(
      spec!.serverId,
      allowed: false,
      expectedRevision: catchupStore.downloadPermissionRevision(spec.serverId),
      isCurrent: () =>
          !cancelled &&
          catchupStore.matchesIdentity(config) &&
          catchupStore.catalogServerId == spec!.serverId,
      baseDir: paths.baseDir,
    );
  }

  try {
    await catchupStore.reload();
    spec = catchupStore.readSpec();
    if (spec == null ||
        catchupStore.paused ||
        catchupStore.downloadPermissionPaused(spec.serverId) ||
        !catchupStore.matchesIdentity(config)) {
      return true;
    }
    ledger = catchupStore.readLedger(spec.serverId);
    needsBackfill = spec.keepRuleMangaIds.difference(ledger.backfilledMangaIds);
    controlTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(checkControls()),
    );
    await checkControls();
    if (cancelled) return true;
    final target = BackgroundServerTarget(
      client: client,
      isCancelled: () => cancelled,
      serverBase: (endpoint ?? config.endpoint).baseUrl,
      port: (endpoint ?? config.endpoint).port,
      addPort: (endpoint ?? config.endpoint).addPort,
    );
    if (!await verifyBackgroundServerIdentity(
      target: target,
      record: record,
      broker: broker,
      expected: spec.serverId,
    )) {
      return true;
    }
    var downloaded = 0;
    var runBytes = 0;
    var storedBytes = 0;
    if (spec.storageCapEnabled) {
      final root = Directory(paths.baseDir);
      if (await root.exists()) {
        await for (final item in root.list(
          recursive: true,
          followLinks: false,
        )) {
          if (cancelled) return true;
          if (item is File &&
              RegExp(r'[/\\][0-9]+[/\\]').hasMatch(item.path) &&
              !item.path.contains('.superseded')) {
            storedBytes += await item.length();
          }
        }
      }
    }
    Future<bool> capBlocked() async =>
        spec!.storageCapEnabled && storedBytes >= spec.storageCapBytes;

    Future<int> chapterBytes(int mangaId, int chapterId) async {
      var bytes = 0;
      for (final relative in [
        paths.chapterDirRel(mangaId, chapterId),
        paths.chapterStagingDirRel(mangaId, chapterId),
      ]) {
        final directory = Directory(paths.absolute(relative));
        if (!await directory.exists()) continue;
        await for (final file in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (file is File) bytes += await file.length();
        }
      }
      return bytes;
    }

    Future<ChapterAttempt> trackedDownload({
      required OfflineChapter row,
      required int mangaId,
      required int generation,
      bool queued = false,
    }) async {
      final capped = spec!.storageCapEnabled;
      final before = capped ? await chapterBytes(mangaId, row.id) : 0;
      try {
        return await _downloadOneChapter(
          target: target,
          record: record,
          broker: broker,
          store: store,
          log: log,
          spec: spec!,
          row: row,
          mangaId: mangaId,
          generation: generation,
          queued: queued,
          isCancelled: () => cancelled,
        );
      } finally {
        if (capped) storedBytes += await chapterBytes(mangaId, row.id) - before;
      }
    }

    final queued = await runQueuedDownloads(
      spec: spec,
      ledger: ledger,
      store: store,
      log: log,
      fetchChapters: (mangaId) async =>
          (await _fetchMangaChapters(target, record, broker, mangaId))?.rows,
      enqueueServer: (chapterId) =>
          _enqueueServerDownload(target, record, broker, chapterId),
      download: (row, chapter) => trackedDownload(
        row: row,
        mangaId: chapter.mangaId,
        generation: chapter.generation,
        queued: true,
      ),
      shouldStop: (chapter) async {
        await checkControls();
        await catchupStore.reload();
        if (!catchupStore.matchesIdentity(config) ||
            catchupStore.paused ||
            catchupStore.downloadPermissionPaused(spec!.serverId)) {
          cancelled = true;
        }
        final current = catchupStore.readSpec();
        if (!(current?.queuedChapters.any(
              (c) =>
                  c.chapterId == chapter.chapterId &&
                  c.generation == chapter.generation,
            ) ??
            false)) {
          cancelled = true;
          client.close();
        }
        return cancelled;
      },
      onPermissionDenied: () async {
        await recordDenial();
      },
      capBlocked: capBlocked,
      persist: (next) async {
        await catchupStore.reload();
        if (catchupStore.catalogServerId != spec!.serverId) {
          cancelled = true;
          return;
        }
        await catchupStore.writeLedger(spec.serverId, next);
        if (!catchupStore.matchesIdentity(config)) cancelled = true;
      },
    );
    ledger = queued.ledger;
    downloaded = queued.completed;
    if (queued.interrupted ||
        cancelled ||
        !catchupStore.enabled ||
        !catchupStore.downloadEnabled) {
      return true;
    }

    // One snapshot is safe only because each manga is visited once and its own new entries are excluded.
    final logEntries = await log.parse();
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
      await checkControls();
      if (cancelled) break;
      final mangaSpec = spec.manga
          .where((m) => m.mangaId == mangaId)
          .firstOrNull;
      if (mangaSpec == null) {
        ledger = _dropManga(ledger, mangaId);
        await catchupStore.writeLedger(spec.serverId, ledger);
        continue;
      }

      final chapters = await _fetchMangaChapters(
        target,
        record,
        broker,
        mangaId,
      );
      if (chapters == null) return false; // transient — retry next wake

      // Pins are device-only; merge the spec pins with the server-derived desired set.
      final serverIds = {for (final r in chapters.rows) r.id};

      final serverFetch = {...ledger.pendingServerFetch};
      final retries = {...ledger.serverFetchRetries};
      final dlRetries = {...ledger.downloadRetries};
      final pending = {...ledger.pendingDownloads};
      final generations = {...ledger.chapterGenerations};
      Future<bool> persistProgress() async {
        await catchupStore.reload();
        if (catchupStore.catalogServerId != spec!.serverId) {
          return false;
        }
        ledger = ledger.copyWith(
          chapterGenerations: generations,
          pendingDownloads: pending,
          pendingServerFetch: serverFetch,
          serverFetchRetries: retries,
          downloadRetries: dlRetries,
        );
        await catchupStore.writeLedger(spec.serverId, ledger);
        return catchupStore.matchesIdentity(config);
      }

      for (final row in chapters.rows) {
        final generation = mangaSpec.generationOf(row.id);
        if ((generations[row.id] ?? 0) != generation) {
          pending.remove(row.id);
          serverFetch.remove(row.id);
          retries.remove(row.id);
          dlRetries.remove(row.id);
          generations.remove(row.id);
        }
        final key = '${row.id}:$generation';
        final serverSpent = math.max(
          retries[row.id] ?? 0,
          math.max(
            ledger.queuedServerRetries[key] ?? 0,
            mangaSpec.serverFetchAttempts[row.id] ?? 0,
          ),
        );
        final deviceSpent = math.max(
          dlRetries[row.id] ?? 0,
          ledger.queuedDownloadRetries[key] ?? 0,
        );
        if (serverSpent > 0 || deviceSpent > 0) {
          generations[row.id] = generation;
          pending[row.id] = mangaId;
        }
        if (serverSpent > 0) retries[row.id] = serverSpent;
        if (deviceSpent > 0) dlRetries[row.id] = deviceSpent;
      }

      final exhausted = <int>{};
      for (final r in chapters.rows) {
        final serverFetchSpent = retries[r.id] ?? 0;
        final downloadSpent = dlRetries[r.id] ?? 0;
        if ((r.serverIsDownloaded ||
                serverFetchSpent < catchupMaxChapterAttempts) &&
            downloadSpent < catchupMaxChapterAttempts) {
          continue;
        }
        exhausted.add(r.id);
        final completed =
            mangaSpec.onDeviceChapterIds.contains(r.id) ||
            mangaSpec.failedChapterIds.contains(r.id) ||
            (await _loggedOrCommitted(logEntries, store, mangaId, {
              r.id,
            })).contains(r.id);
        if (!completed) {
          await catchupStore.reload();
          if (cancelled || !catchupStore.matchesIdentity(config)) return true;
          final generation = mangaSpec.generationOf(r.id);
          final failure = AdoptChapterEntry(
            chapterId: r.id,
            mangaId: mangaId,
            serverId: spec.serverId,
            name: r.name,
            chapterIndex: r.chapterIndex,
            chapterNumber: r.chapterNumber ?? -1,
            pageCount: r.pageCount,
            bytes: 0,
            isRead: r.isRead,
            status: 'error',
            generation: generation,
          );
          await log.appendAdopt(failure);
          await log.appendChapter(
            chapterId: r.id,
            status: 'error',
            pages: 0,
            bytes: 0,
            generation: generation,
          );
        }

        recordDiagnostic(
          '[${DateTime.now().toIso8601String()}] offline-catchup: '
          'giving-up-on-chapter mangaId=$mangaId chapterId=${r.id} '
          'name="${r.name}" index=${r.chapterIndex} '
          'serverFetchAttempts=$serverFetchSpent/$catchupMaxChapterAttempts '
          'downloadAttempts=$downloadSpent/$catchupMaxChapterAttempts '
          'serverIsDownloaded=${r.serverIsDownloaded} '
          '— excluded from this manga\'s keep-rule slots from now on\n',
        );
      }
      final desired = desiredChapterIds(
        [
          for (final r in chapters.rows)
            if (!exhausted.contains(r.id) &&
                !mangaSpec.failedChapterIds.contains(r.id))
              r,
        ],
        mangaSpec.keepRule,
        mangaSpec.keepUnreadCount,
        sortAxis: mangaSpec.chapterSortMode,
      )..addAll(mangaSpec.pinnedChapterIds.intersection(serverIds));

      final present = <int>{
        ...mangaSpec.onDeviceChapterIds,
        ...mangaSpec.failedChapterIds,
        ...spec.queuedChapters.map((chapter) => chapter.chapterId),
        ...await _loggedOrCommitted(logEntries, store, mangaId, desired),
      };

      final toDownload = desired.difference(present);
      if (toDownload.isNotEmpty) {
        recordDiagnostic(
          '[${DateTime.now().toIso8601String()}] offline-catchup: '
          'manga-plan mangaId=$mangaId keepRule=${mangaSpec.keepRule.name} '
          'keepN=${mangaSpec.keepUnreadCount} desired=${desired.length} '
          'onDevice=${mangaSpec.onDeviceChapterIds.length} '
          'toDownload=[${toDownload.join(',')}]\n',
        );
      }
      for (final chapterId in toDownload) {
        pending[chapterId] = mangaId;
        generations[chapterId] = mangaSpec.generationOf(chapterId);
      }
      for (final chapterId in toDownload) {
        if (downloaded >= _maxChaptersPerRun) break;
        if (DateTime.now().isAfter(deadline)) break;
        if (await capBlocked()) {
          final partial = await store.readManifest(mangaId, chapterId);
          if (partial?.generation != mangaSpec.generationOf(chapterId) ||
              await store.stagedBytes(mangaId, chapterId) == 0) {
            continue;
          }
        }
        await checkControls();
        if (cancelled) break;
        final row = chapters.byId[chapterId];
        if (row == null) continue;

        // Keep separate per-hop budgets across runs; only success or leaving the window resets them.
        try {
          if (!row.serverIsDownloaded) {
            final spent = retries[chapterId] ?? 0;
            if (spent >= catchupMaxChapterAttempts) {
              recordDiagnostic(
                '[${DateTime.now().toIso8601String()}] offline-catchup: '
                'skip-chapter mangaId=$mangaId chapterId=$chapterId '
                'reason=server-fetch-budget-exhausted '
                'attempts=$spent/$catchupMaxChapterAttempts\n',
              );
              serverFetch.remove(chapterId);
              continue;
            }
            final ok = await _enqueueServerDownload(
              target,
              record,
              broker,
              chapterId,
            );
            recordDiagnostic(
              '[${DateTime.now().toIso8601String()}] offline-catchup: '
              'asking-server-to-fetch mangaId=$mangaId chapterId=$chapterId '
              'name="${row.name}" index=${row.chapterIndex} '
              'enqueueOk=$ok attempt=${spent + 1}/$catchupMaxChapterAttempts\n',
            );
            if (ok) {
              serverFetch[chapterId] = mangaId;
              retries[chapterId] = spent + 1;
              if (!await persistProgress()) return true;
            }
            continue;
          }

          serverFetch.remove(chapterId);
          final dlSpent = dlRetries[chapterId] ?? 0;
          if (dlSpent >= catchupMaxChapterAttempts) {
            recordDiagnostic(
              '[${DateTime.now().toIso8601String()}] offline-catchup: '
              'skip-chapter mangaId=$mangaId chapterId=$chapterId '
              'reason=download-budget-exhausted '
              'attempts=$dlSpent/$catchupMaxChapterAttempts\n',
            );
            continue;
          }

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

          final attempt = await trackedDownload(
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
            generations.remove(chapterId);
            recordDiagnostic(
              '[${DateTime.now().toIso8601String()}] offline-catchup: '
              'downloaded-chapter mangaId=$mangaId chapterId=$chapterId '
              'bytes=${attempt.bytes}\n',
            );
          } else if (!attempt.transient) {
            dlRetries[chapterId] = dlSpent + 1;
            recordDiagnostic(
              '[${DateTime.now().toIso8601String()}] offline-catchup: '
              'download-failed mangaId=$mangaId chapterId=$chapterId '
              'transient=false '
              'attempt=${dlSpent + 1}/$catchupMaxChapterAttempts\n',
            );
          } else {
            recordDiagnostic(
              '[${DateTime.now().toIso8601String()}] offline-catchup: '
              'download-deferred mangaId=$mangaId chapterId=$chapterId '
              'reason=transient\n',
            );
          }
          if (!await persistProgress()) return true;
          if (cancelled) break outer;
        } on AccountPermissionDenied {
          if (!await recordDenial() ||
              cancelled ||
              !catchupStore.matchesIdentity(config)) {
            return true;
          }
          await log.appendAdopt(
            AdoptChapterEntry(
              chapterId: row.id,
              mangaId: mangaId,
              serverId: spec.serverId,
              name: row.name,
              chapterIndex: row.chapterIndex,
              chapterNumber: row.chapterNumber ?? -1,
              pageCount: row.pageCount,
              bytes: 0,
              isRead: row.isRead,
              status: 'permissionDenied',
              generation: mangaSpec.generationOf(chapterId),
            ),
          );
          await log.appendChapter(
            chapterId: chapterId,
            status: 'permissionDenied',
            pages: 0,
            bytes: 0,
            generation: mangaSpec.generationOf(chapterId),
          );
          await persistProgress();
          return true;
        }
      }

      // Clear satisfied or no-longer-desired obligations from both maps.
      // Exhaustion also excludes a chapter from desired; preserve its spent budget until it leaves the window.
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
        generations.remove(c);
      }

      ledger = ledger.copyWith(
        chapterGenerations: generations,
        pendingDownloads: pending,
        pendingServerFetch: serverFetch,
        serverFetchRetries: retries,
        downloadRetries: dlRetries,
        backfilledMangaIds: {...ledger.backfilledMangaIds, mangaId},
      );
      if (!await persistProgress()) return true;
    }
    recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] offline-catchup: '
      'run-finished downloaded=$downloaded bytes=$runBytes\n',
    );
    return true;
  } on AccountPermissionDenied {
    await recordDenial();
    return true;
  } finally {
    controlTimer?.cancel();
    client.close();
    await controlCheck;
    await lock.release();
    await reconcileBackgroundSchedule();
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
    chapterGenerations: without(ledger.chapterGenerations),
    pendingDownloads: without(ledger.pendingDownloads),
    pendingServerFetch: without(ledger.pendingServerFetch),
    serverFetchRetries: without(ledger.serverFetchRetries),
    downloadRetries: without(ledger.downloadRetries),
    backfilledMangaIds: {...ledger.backfilledMangaIds}..remove(mangaId),
  );
}

// Staging alone is not durable adoption: require a log record or committed directory.
Future<Set<int>> _loggedOrCommitted(
  List<LogEntry> logEntries,
  IoOfflinePageStore store,
  int mangaId,
  Set<int> candidates,
) async {
  final present = <int>{};
  final generations = <int, int>{};
  for (final e in logEntries) {
    if (e is DeletedEntry && e.generation >= (generations[e.chapterId] ?? 0)) {
      generations[e.chapterId] = e.generation;
      present.remove(e.chapterId);
    }
    if (e is AdoptChapterEntry &&
        e.mangaId == mangaId &&
        e.generation >= (generations[e.chapterId] ?? 0)) {
      present.add(e.chapterId);
    }
    if (e is ChapterEntry &&
        (e.status == 'downloaded' ||
            e.status == 'permissionDenied' ||
            e.status == 'error') &&
        e.generation >= (generations[e.chapterId] ?? 0)) {
      generations[e.chapterId] = e.generation;
      present.add(e.chapterId);
    }
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

/// Null when the server was unreachable.
Future<_MangaChapters?> _fetchMangaChapters(
  BackgroundServerTarget target,
  BackgroundTokenRecord Function() record,
  TokenBroker broker,
  int mangaId,
) async {
  const query =
      'query MangaChapters(\$id: Int!){ chapters(condition:{mangaId: \$id}, order:[{by: SOURCE_ORDER, byType: ASC}]){ nodes { id name sourceOrder chapterNumber uploadDate fetchedAt user { isRead isBookmarked isDownloaded } pageCount } } }';
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
  if (result == gqlNetworkError ||
      result == gqlAuthError ||
      (target.isCancelled?.call() ?? false)) {
    return null;
  }
  if (result is! Map<String, Object?>) return null;
  final nodes = (result['chapters'] as Map<String, Object?>?)?['nodes'];
  if (nodes is! List) return null;
  final now = DateTime.now();
  return _MangaChapters([
    for (final n in nodes.cast<Map<String, Object?>>())
      OfflineChapter(
        id: (n['id'] as num).toInt(),
        mangaId: mangaId,
        name: n['name'] as String? ?? '',
        chapterIndex: (n['sourceOrder'] as num?)?.toInt() ?? 0,
        chapterNumber: (n['chapterNumber'] as num?)?.toDouble(),
        uploadDate: n['uploadDate'] as String?,
        fetchedAt: n['fetchedAt'] as String?,
        isRead:
            (n['user'] as Map<String, Object?>?)?['isRead'] as bool? ?? false,
        lastPageRead: 0,
        isBookmarked:
            (n['user'] as Map<String, Object?>?)?['isBookmarked'] as bool? ??
            false,
        serverIsDownloaded:
            (n['user'] as Map<String, Object?>?)?['isDownloaded'] as bool? ??
            false,
        deviceState: OfflineDeviceState.none,
        pageCount: (n['pageCount'] as num?)?.toInt() ?? 0,
        bytes: 0,
        pinned: false,
        downloadedAt: null,
        progressDirty: false,
        bookmarkDirty: false,
        readStateDirty: false,
        readStateManual: false,
        syncedIsRead:
            (n['user'] as Map<String, Object?>?)?['isRead'] as bool? ?? false,
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
  if (!await verifyBackgroundDownloadAccess(
    target: target,
    record: record,
    broker: broker,
  )) {
    return false;
  }
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
  // Retry with refreshed auth: the broker persists refreshes without updating record().
  var result = await post(null);
  if (result == gqlAuthError && record().authType == 'uiLogin') {
    final newAccess = await broker.resolveAfter401(record().accessToken ?? '');
    if (newAccess != null) result = await post(newAccess);
  }
  return !(target.isCancelled?.call() ?? false) &&
      result is Map<String, Object?> &&
      result['enqueueChapterDownloads'] is Map;
}

/// Transient outages do not consume the chapter failure budget.
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
  bool queued = false,
  bool Function()? isCancelled,
}) async {
  final urls = await resolveChapterPageUrls(
    target: target,
    record: record,
    broker: broker,
    chapterId: row.id,
  );
  // Null means unreachable; empty means the server answered with no pages.
  if ((isCancelled?.call() ?? false) || urls == null) {
    return (bytes: 0, transient: true);
  }
  if (urls.isEmpty) return (bytes: 0, transient: false);

  final indices = [for (var i = 0; i < urls.length; i++) i];
  // Preserve spec generations and resume matching staging so interrupted runs can make progress.
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
    isCancelled: isCancelled ?? () => false,
    onPageStored: (_, _, _) async {},
  );
  if (outcome.cancelled) {
    return (bytes: 0, transient: true);
  }
  if (outcome.error is AccountPermissionDenied) throw outcome.error!;
  if (!outcome.succeeded) {
    return (bytes: 0, transient: outcome.offline || outcome.authFailed);
  }
  if (isCancelled?.call() ?? false) {
    return (bytes: 0, transient: true);
  }

  // Account the whole staged chapter, including pages downloaded by earlier runs.
  final bytes = await store.stagedBytes(mangaId, row.id);
  if (!queued) {
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
  }
  return (bytes: bytes, transient: false);
}
