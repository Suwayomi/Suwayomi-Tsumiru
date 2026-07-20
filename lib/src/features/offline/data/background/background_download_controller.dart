// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/db_keys.dart';
import '../../../../constants/enum.dart';
import '../../../../global_providers/global_providers.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/logger/logger.dart';
import '../../../auth/data/auth_credentials_store.dart';
import '../../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../offline_database.dart';
import '../offline_page_store.dart';
import '../offline_paths.dart';
import '../offline_repository.dart';
import '../offline_settings_providers.dart';
import 'background_completion_log.dart';
import 'background_token_record.dart';
import 'background_work_order.dart';
import 'download_task_handler.dart';

/// Owns the Android foreground-service download worker from the MAIN isolate —
/// starts/stops it, mirrors drift into it, and applies its events + completion
/// log back into drift. Single-owner invariant: exactly one isolate downloads
/// while the queue is non-empty on Android, so the main-isolate pump must never
/// run there; on other platforms this controller is a no-op and the
/// main-isolate pump is used instead.
class BackgroundDownloadController with WidgetsBindingObserver {
  BackgroundDownloadController(this._ref);

  final Ref _ref;

  /// The chapter's persistent download generation (bumped on each delete),
  /// stamped into every worker message so a terminal event from an older
  /// generation is dropped. Persisted so it survives a restart — an in-memory
  /// counter would let a re-queued download reuse a generation.
  int _genOf(OfflineChapter c) => c.downloadGeneration;

  /// Registered as the FFT task-data callback; held so we can deregister.
  DataCallback? _workerEventCallback;

  /// Connectivity listener used to enforce Wi-Fi-only while the app is alive.
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  /// Guards [ensureServiceRunning] against overlapping invocations (it does
  /// several awaited steps; concurrent enqueue + resume could double-start).
  bool _ensuring = false;
  bool _suppressRestarts = false;

  OfflineDatabase get _db => _ref.read(offlineDatabaseProvider);
  OfflinePaths get _paths => _ref.read(offlinePathsProvider);
  OfflinePageStore get _store => _ref.read(offlinePageStoreProvider);

  BackgroundCompletionLog get _log =>
      BackgroundCompletionLog(File('${_paths.baseDir}/.bg_completion.log'));

  // ---------------------------------------------------------------------------
  // Lifecycle registration
  // ---------------------------------------------------------------------------

  /// Wire up the worker-event callback + Wi-Fi-only listener. Call once at
  /// startup (after FFT.initCommunicationPort, before/at launch replay);
  /// idempotent.
  void register() {
    if (!Platform.isAndroid) return;
    WidgetsBinding.instance.addObserver(this);
    _workerEventCallback ??= _onWorkerEvent;
    FlutterForegroundTask.addTaskDataCallback(_workerEventCallback!);
    _connSub ??=
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final cb = _workerEventCallback;
    if (cb != null) FlutterForegroundTask.removeTaskDataCallback(cb);
    unawaited(_connSub?.cancel());
  }

  // ---------------------------------------------------------------------------
  // Service start (heart of single-owner)
  // ---------------------------------------------------------------------------

  /// Ensure the foreground service owns the current queue — idempotent: merges
  /// pending ids into an already-running worker, else starts one with a fresh
  /// work order. Wi-Fi-only is enforced here: won't start on a metered
  /// connection when the setting is on.
  Future<void> ensureServiceRunning() async {
    if (!Platform.isAndroid) return;
    if (_suppressRestarts) return;
    // PAUSE GATE — first line so every restart path (start, onEnqueued,
    // replayOnResume, launch replay, drain/stop handlers, connectivity-resume)
    // inherits it.
    if (_isPaused()) return;
    if (_ensuring) return;
    _ensuring = true;
    try {
      final pending = await _pendingChapters();
      if (pending.isEmpty) return;

      if (await FlutterForegroundTask.isRunningService) {
        // Already owned — just merge the new ids into the worker's queue.
        for (final c in pending) {
          FlutterForegroundTask.sendDataToTask({
            'op': 'add',
            'chapterId': c.id,
            'mangaId': c.mangaId,
            'gen': _genOf(c),
          });
        }
        return;
      }

      // Start gate: don't bring up the service on metered + Wi-Fi-only; the
      // queue stays in drift until a Wi-Fi reconnect or next foreground starts
      // it.
      if (await _wifiOnlyBlocks()) {
        logger.i('Offline: Wi-Fi-only on + metered — deferring service start');
        return;
      }

      await _ensureNotificationPermission();
      await _writeWorkOrder(pending);
      // Re-check the pause gate: a pause could have landed while we awaited the
      // steps above, and pause() only messages a *running* service — without
      // this recheck we'd start straight into a paused state.
      if (_isPaused()) return;
      final res = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: 'Downloading chapters',
        notificationText: 'Starting…',
        callback: backgroundDownloadCallback,
      );
      if (res is ServiceRequestFailure) {
        logger.e('Offline: foreground service failed to start: ${res.error}');
      }
    } finally {
      _ensuring = false;
    }
  }

  /// drift is queue authority: queued + (resumable) downloading chapters.
  Future<List<OfflineChapter>> _pendingChapters() async {
    final queued = await _db.chaptersInState(OfflineDeviceState.queued);
    final downloading =
        await _db.chaptersInState(OfflineDeviceState.downloading);
    return [...queued, ...downloading];
  }

  // ---------------------------------------------------------------------------
  // Enqueue / remove / wifi-only changes
  // ---------------------------------------------------------------------------

  /// Called after the caller has written drift `queued` for [chapterIds]. Just
  /// ensures the service owns the queue (it reads drift, not the argument).
  Future<void> onEnqueued(List<int> chapterIds) => ensureServiceRunning();

  /// True when the user has paused all on-device downloads (persisted flag).
  /// Read synchronously so the start gate can't be bypassed by an unhydrated
  /// provider read.
  bool _isPaused() =>
      _ref
          .read(sharedPreferencesProvider)
          .getBool(DBKeys.offlineDownloadsPaused.name) ??
      false;

  /// Pause all on-device downloads: tell the worker to park the in-flight
  /// chapter and self-stop. Caller persists the flag first; the start gate in
  /// [ensureServiceRunning] then blocks restart until [resume].
  Future<void> pause() async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      // Graceful: the worker cancels + self-stops. Never main-side stopService
      // here — it would race the worker and could corrupt a half-written page.
      FlutterForegroundTask.sendDataToTask({'op': 'pause'});
    }
  }

  /// Resume on-device downloads (caller has cleared the persisted flag first).
  Future<void> resume() => ensureServiceRunning();

  Future<void> stopAndClearWorkOrder() async {
    if (!Platform.isAndroid) return;
    _suppressRestarts = true;
    await pause();
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    for (var i = 0; i < 20; i++) {
      if (!await FlutterForegroundTask.isRunningService) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await FlutterForegroundTask.removeData(key: kWorkOrderKey);
    await FlutterForegroundTask.removeData(key: kTokenRecordKey);
    final log = _log;
    if (await log.file.exists()) await log.file.delete();
  }

  void finishCatalogClear() {
    _suppressRestarts = false;
  }

  /// Tell the worker to drop a chapter (delete/cancel). The caller still does
  /// the actual drift/file delete; this only stops the in-flight download.
  Future<void> onRemoved(int chapterId) async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(
          {'op': 'remove', 'chapterId': chapterId});
    }
  }

  /// Record a delete tombstone at [newGeneration] (already bumped in drift) so
  /// a stale entry from the previous generation can't complete the chapter
  /// after it's re-queued.
  Future<void> recordChapterDeleted(int chapterId, int newGeneration) async {
    if (!Platform.isAndroid) return;
    await _log.appendDeleted(chapterId, newGeneration);
  }

  /// Push a Wi-Fi-only setting change to the worker, and enforce it from the
  /// main side: if it's now on + we're metered, stop the running service.
  Future<void> onWifiOnlyChanged(bool value) async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(
          {'op': 'setWifiOnly', 'value': value});
      if (value && await _isMetered()) {
        await FlutterForegroundTask.stopService();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // App lifecycle
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isAndroid) return;
    if (state == AppLifecycleState.resumed) {
      // Catch drift up from the durable log for live UI. No ownership change —
      // the worker still owns the queue.
      unawaited(replayOnResume());
    }
    // paused/hidden/detached: NOTHING — the FGS already owns the queue.
  }

  /// Replay the completion log into drift (live-UI catch-up on resume).
  Future<void> replayOnResume() async {
    await _replay();
    // The FGS may have been killed while backgrounded (OOM, the dataSync time
    // cap, a swipe-away); restart if pending work remains — ensureServiceRunning
    // is idempotent/no-op if the worker's still alive.
    final pending = await _pendingChapters();
    if (pending.isNotEmpty) await ensureServiceRunning();
  }

  /// At launch: replay any log left by a previous run, then — if drift still has
  /// a non-empty queue — (re)start the service to finish it.
  Future<void> replayAtLaunchAndMaybeStart() async {
    if (!Platform.isAndroid) return;
    await _replay();
    final pending = await _pendingChapters();
    if (pending.isNotEmpty) await ensureServiceRunning();
  }

  Future<void> _replay() => replayCompletionLog(
        db: _db,
        paths: _paths,
        log: _log,
        measureBytes: (mangaId, chapterId) =>
            _store.chapterBytes(mangaId, chapterId),
      );

  // ---------------------------------------------------------------------------
  // Worker events + drain handshake (CRITICAL-1)
  // ---------------------------------------------------------------------------

  void _onWorkerEvent(Object data) {
    if (data is! Map) return;
    // During a catalog clear the worker is being torn down; a page/chapter
    // event still queued in the SendPort would otherwise re-insert a row into
    // the just-wiped catalog — drop everything until the clear releases the flag.
    if (_suppressRestarts) return;
    switch (data['kind']) {
      // Live foreground UI only — mark downloading + accumulate page rows so
      // the progress arc animates; the durable record is the completion log,
      // replayed on resume.
      case 'chapterStart':
        unawaited(_applyChapterStart(data['chapterId'] as int,
            data['total'] as int?, data['gen'] as int? ?? 0));
      case 'page':
        unawaited(_applyPageEvent(data));
      case 'chapterDone':
        unawaited(_onChapterDone(data));
      case 'drained':
        unawaited(_onDrained());
    }
  }

  /// Apply a `chapterStart` inside a transaction that checks the chapter isn't
  /// deleted first — a remove message can cross the isolate boundary after
  /// already-queued worker events, so this guard (serialized with
  /// deleteChapter) drops it instead of resurrecting a `none` chapter.
  Future<void> _applyChapterStart(int id, int? total, int eventGen) async {
    await _db.transaction(() async {
      final c = await _db.chapterById(id);
      if (c == null || c.deviceState == OfflineDeviceState.none) return;
      if (eventGen < c.downloadGeneration) return; // stale generation
      await _db.setChapterDeviceState(id, OfflineDeviceState.downloading);
      // Only set a known total over an unset/0 one, to avoid clobbering a good
      // catalog value.
      if (total != null && total > 0) {
        await _db.setChapterPageCount(id, total);
      }
    });
  }

  Future<void> _applyPageEvent(Map data) async {
    final id = data['chapterId'] as int;
    final eventGen = data['gen'] as int? ?? 0;
    await _db.transaction(() async {
      final c = await _db.chapterById(id);
      if (c == null || c.deviceState == OfflineDeviceState.none) return;
      if (eventGen < c.downloadGeneration) return; // stale generation
      await _db.into(_db.offlinePages).insertOnConflictUpdate(
            OfflinePagesCompanion.insert(
              chapterId: id,
              pageIndex: data['pageIndex'] as int,
              relativePath: data['relPath'] as String,
            ),
          );
    });
  }

  /// The worker drained and is self-stopping. Anything queued during that
  /// shutdown window is stranded (the "tap download, nothing happens until
  /// reopen" bug), so wait for the stop to actually complete, then recheck and
  /// restart if work remains.
  Future<void> _onDrained() async {
    for (var i = 0; i < 20; i++) {
      if (!await FlutterForegroundTask.isRunningService) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    final pending = await _pendingChapters();
    if (pending.isNotEmpty) await ensureServiceRunning();
  }

  Future<void> _onChapterDone(Map data) async {
    final chapterId = data['chapterId'] as int?;
    final status = data['status'] as String?;
    if (chapterId != null && status != null) {
      // Measure bytes outside the transaction (filesystem read); the
      // terminal-state apply rechecks so a chapterDone landing after a delete
      // can't flip a `none` chapter back to downloaded/error.
      int bytes = 0;
      if (status == 'downloaded') {
        final ch = await _db.chapterById(chapterId);
        if (ch != null) bytes = await _store.chapterBytes(ch.mangaId, chapterId);
      }
      await applyBackgroundTerminalState(
          db: _db,
          chapterId: chapterId,
          status: status,
          bytes: bytes,
          eventGeneration: data['gen'] as int? ?? 0);
    }

    // Drain handshake: if the worker just self-stopped, do post-stop
    // reconciliation + a drift requery in case work was enqueued during the
    // async stop window (CRITICAL-1).
    if (!await FlutterForegroundTask.isRunningService) {
      await _onServiceStopped();
    }
  }

  Future<void> _onServiceStopped() async {
    await _replay(); // final log replay → drift
    await _wipeWorkOrderAuth();
    // Anything queued during the async stop? Restart to pick it up.
    final pending = await _pendingChapters();
    if (pending.isNotEmpty) await ensureServiceRunning();
  }

  // ---------------------------------------------------------------------------
  // Work order + auth snapshot / write-back
  // ---------------------------------------------------------------------------

  Future<void> _writeWorkOrder(List<OfflineChapter> pending) async {
    final auth = _snapshotAuth();
    final order = BackgroundWorkOrder(
      chapterIds: [for (final c in pending) c.id],
      mangaIdByChapter: {for (final c in pending) c.id: c.mangaId},
      generationByChapter: {for (final c in pending) c.id: _genOf(c)},
      serverBase: _ref.read(serverUrlProvider) ?? '',
      port: _ref.read(serverPortProvider),
      addPort: _ref.read(serverPortToggleProvider).ifNull(),
      wifiOnly: _ref.read(offlineWifiOnlyProvider) ?? true,
      auth: auth,
      baseDir: _paths.baseDir,
    );
    await FlutterForegroundTask.saveData(
        key: kWorkOrderKey, value: jsonEncode(order.toJson()));
    // Seed the shared token record so the worker's broker reads/writes the same
    // gen-versioned record we'll read back on stop.
    await FlutterForegroundTask.saveData(
        key: kTokenRecordKey, value: jsonEncode(auth.toJson()));
  }

  /// Snapshot the current auth into the cross-isolate record. The worker uses
  /// only the fields relevant to the active auth type.
  BackgroundTokenRecord _snapshotAuth() {
    final authType = _ref.read(authTypeKeyProvider) ?? AuthType.none;
    final basicToken = _ref.read(credentialsProvider).value;
    final creds = _ref.read(authCredentialsStoreProvider).value;
    return BackgroundTokenRecord(
      gen: 0,
      authType: authType.name,
      endpoint: _effectiveEndpoint(),
      accessToken: creds?.uiAccessToken,
      refreshToken: creds?.uiRefreshToken,
      basicCredential: basicToken,
      simpleCookie: creds?.simpleLoginCookie,
    );
  }

  /// Endpoint identity (URL + custom port if enabled) the client talks to.
  String _effectiveEndpoint() {
    final usePort = _ref.read(serverPortToggleProvider).ifNull();
    final port = usePort ? _ref.read(serverPortProvider) : null;
    return '${_ref.read(serverUrlProvider)}|${port ?? '-'}';
  }

  /// After the worker stops, copy any rotated ui_login tokens back into
  /// [AuthCredentialsStore], then clear the FFT auth keys so a stale snapshot
  /// doesn't linger in plugin storage.
  Future<void> _wipeWorkOrderAuth() async {
    final raw =
        await FlutterForegroundTask.getData<String>(key: kTokenRecordKey);
    if (raw != null) {
      try {
        final record = BackgroundTokenRecord.fromJson(
            jsonDecode(raw) as Map<String, Object?>);
        // gen > 0 means the worker rotated the token at least once. Endpoint
        // check skips writeback if the user switched servers meanwhile.
        if (record.gen > 0 &&
            record.authType == 'uiLogin' &&
            record.accessToken != null &&
            record.endpoint == _effectiveEndpoint()) {
          final store = _ref.read(authCredentialsStoreProvider.notifier);
          // Epoch guard covers a switch landing during the writeback itself.
          final epoch = store.serverEpoch;
          if (record.refreshToken != null) {
            await store.saveUiLoginTokens(
              accessToken: record.accessToken!,
              refreshToken: record.refreshToken!,
              forEpoch: epoch,
            );
          } else {
            await store.updateUiLoginAccessToken(record.accessToken!,
                forEpoch: epoch);
          }
        }
      } catch (e) {
        logger.e('Offline: failed to read back worker token record: $e');
      }
    }
    await FlutterForegroundTask.removeData(key: kTokenRecordKey);
    await FlutterForegroundTask.removeData(key: kWorkOrderKey);
  }

  // ---------------------------------------------------------------------------
  // Wi-Fi-only main-side enforcement
  // ---------------------------------------------------------------------------

  /// True when Wi-Fi-only is set AND the active connection is metered — the
  /// condition under which we won't start the service.
  Future<bool> _wifiOnlyBlocks() async {
    if (!(_ref.read(offlineWifiOnlyProvider) ?? true)) return false;
    return _isMetered();
  }

  /// True when the active connection is metered (no Wi-Fi/ethernet).
  /// `connectivity_plus` returns a list; empty/none is treated as metered-ish
  /// so a wifi-only batch doesn't start.
  Future<bool> _isMetered() async {
    final result = await Connectivity().checkConnectivity();
    final hasUnmetered = result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
    return !hasUnmetered;
  }

  /// React to connectivity changes while the app is alive: stop the service on
  /// a drop to metered under Wi-Fi-only (chapters stay `downloading`, resume on
  /// Wi-Fi), or start it on a (re)gained connection with pending work.
  /// LIMITATION: a switch entirely while backgrounded isn't caught here — only
  /// reconciled on the next foreground/launch.
  void _onConnectivityChanged(List<ConnectivityResult> result) {
    if (!Platform.isAndroid) return;
    final wifiOnly = _ref.read(offlineWifiOnlyProvider) ?? true;
    final hasUnmetered = result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
    final hasConnection =
        result.any((r) => r != ConnectivityResult.none) && result.isNotEmpty;
    unawaited(() async {
      if (wifiOnly && !hasUnmetered) {
        // Wi-Fi-only and dropped to metered: stop the running service (chapters
        // stay `downloading` and resume on Wi-Fi).
        if (await FlutterForegroundTask.isRunningService) {
          logger
              .i('Offline: dropped to metered with Wi-Fi-only — stopping FGS');
          await FlutterForegroundTask.stopService();
        }
        return;
      }
      // A usable link returned — resume pending work; covers a queue parked by
      // a resolve-time network drop that would otherwise strand until app
      // resume.
      if (hasConnection) {
        final pending = await _pendingChapters();
        if (pending.isNotEmpty) await ensureServiceRunning();
      }
    }());
  }

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  /// Request POST_NOTIFICATIONS (Android 13+) before starting the service —
  /// `startService` fails without it. Best-effort: a denial is only logged,
  /// and the start still proceeds.
  Future<void> _ensureNotificationPermission() async {
    final current = await FlutterForegroundTask.checkNotificationPermission();
    if (current == NotificationPermission.granted) return;
    final result = await FlutterForegroundTask.requestNotificationPermission();
    if (result != NotificationPermission.granted) {
      logger.i('Offline: notification permission not granted ($result)');
    }
  }

  // ---------------------------------------------------------------------------
  // TokenBroker adapter (main side)
  // ---------------------------------------------------------------------------

  /// A [TokenBroker] backed by FFT storage, sharing the worker's gen-versioned
  /// record — for callers/tests coordinating a refresh from the main isolate.
  /// Only ui_login refreshes; network refresh is delegated to [refreshFn].
  TokenBroker mainSideBroker({
    required Future<RefreshResult?> Function(String refreshToken) refreshFn,
  }) =>
      TokenBroker(
        read: () async {
          final raw =
              await FlutterForegroundTask.getData<String>(key: kTokenRecordKey);
          if (raw != null) {
            return BackgroundTokenRecord.fromJson(
                jsonDecode(raw) as Map<String, Object?>);
          }
          return _snapshotAuth();
        },
        write: (r) => FlutterForegroundTask.saveData(
            key: kTokenRecordKey, value: jsonEncode(r.toJson())),
        refreshFn: refreshFn,
      );
}

/// App-lifetime singleton driving the foreground-service downloads on
/// Android; read at launch (register + replay) and from enqueue/delete sites.
/// No-op on iOS/desktop; on web this file isn't compiled at all —
/// `background_download_controller_shim.dart` swaps in a stub.
final backgroundDownloadControllerProvider =
    Provider<BackgroundDownloadController>(
        (Ref ref) => BackgroundDownloadController(ref));

/// Initialise `flutter_foreground_task` (communication port + notification
/// channel/options). Call once early in `main()`. Android-only; no-op elsewhere.
void initForegroundTaskService() {
  if (!Platform.isAndroid) return;
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'tsumiru_downloads',
      channelName: 'Downloads',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      allowWifiLock: true,
    ),
  );
}
