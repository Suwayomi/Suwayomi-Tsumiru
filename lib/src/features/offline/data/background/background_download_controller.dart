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

/// Owns the Android foreground-service download worker from the MAIN isolate:
/// starts/stops it at the right moments, mirrors drift into the worker via
/// messages, applies the worker's events + the durable completion log back into
/// drift, and recovers correctly after backgrounding / a kill.
///
/// Single-owner invariant: while the queue is non-empty on Android, exactly one
/// background isolate downloads (foreground + background). The main-isolate
/// file-writing pump must NOT run on Android — that gate lives in
/// `initOfflineDownloads` (wired in a later task), not here.
///
/// This controller is a no-op on non-Android platforms; desktop/iOS keep the
/// existing main-isolate pump.
class BackgroundDownloadController with WidgetsBindingObserver {
  BackgroundDownloadController(this._ref);

  final Ref _ref;

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

  /// Wire up the worker-event callback + the Wi-Fi-only connectivity listener.
  /// Call once at startup (after FFT.initCommunicationPort, before/at launch
  /// replay). Idempotent.
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

  /// Ensure the foreground service owns the current queue. Idempotent: if it's
  /// already running, the pending ids are messaged in (the worker merges them);
  /// otherwise the service is started with a freshly-built work order.
  ///
  /// Wi-Fi-only is enforced HERE (main isolate): if the setting is on and the
  /// active connection is metered, the service is not started.
  Future<void> ensureServiceRunning() async {
    if (!Platform.isAndroid) return;
    if (_suppressRestarts) return;
    // PAUSE GATE — first line so EVERY restart path inherits it: the public
    // start, onEnqueued, replayOnResume, replayAtLaunchAndMaybeStart, _onDrained,
    // _onServiceStopped, and the connectivity-resume branch all funnel here.
    if (_isPaused()) return;
    if (_ensuring) return;
    _ensuring = true;
    try {
      final pending = await _pendingChapters();
      if (pending.isEmpty) return;

      if (await FlutterForegroundTask.isRunningService) {
        // Already owned — just merge the new ids into the worker's queue.
        for (final c in pending) {
          FlutterForegroundTask.sendDataToTask(
              {'op': 'add', 'chapterId': c.id, 'mangaId': c.mangaId});
        }
        return;
      }

      // Start gate: don't bring up the service on a metered connection when
      // Wi-Fi-only is on. The queue stays in drift; a later Wi-Fi reconnect (or
      // the next foreground) starts it.
      if (await _wifiOnlyBlocks()) {
        logger.i('Offline: Wi-Fi-only on + metered — deferring service start');
        return;
      }

      await _ensureNotificationPermission();
      await _writeWorkOrder(pending);
      // Re-check the pause gate: a pause could have landed while we awaited the
      // steps above (this call passed the gate at the top before the user
      // paused). Without this, we'd start the service into a paused state, and
      // pause() — which only messages a *running* service — would have skipped
      // it because the service wasn't up yet.
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
  /// chapter and self-stop. The caller persists the flag first; the start gate
  /// in [ensureServiceRunning] then prevents any restart until [resume].
  Future<void> pause() async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      // Graceful: the worker cancels the active chapter (left resumable) and
      // self-stops. Never main-side stopService here — that would race the
      // worker and could corrupt a half-written page.
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
    // The foreground service may have been killed while we were backgrounded (OS
    // memory pressure, the dataSync time cap, a swipe-away). If drift still has
    // pending chapters, (re)start it — ensureServiceRunning is idempotent, so
    // it's a no-op when the worker is still alive. Without this, downloads only
    // resumed when the user reopened a manga's details (which calls it too).
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
    // During a catalog clear the worker is being torn down; a page/chapter event
    // still in the SendPort queue would otherwise re-insert a row into the
    // just-wiped catalog. Drop everything until the clear releases the flag.
    if (_suppressRestarts) return;
    switch (data['kind']) {
      // Live foreground UI: mark the chapter downloading + accumulate page rows
      // as the worker reports them, so the per-chapter progress arc animates.
      // (Only meaningful while the app is foreground; the durable record is the
      // completion log, replayed on resume.)
      case 'chapterStart':
        final id = data['chapterId'] as int;
        unawaited(
            _db.setChapterDeviceState(id, OfflineDeviceState.downloading));
        // Record the resolved page total so the progress arc can show a real
        // fraction (only when known + currently unset/0, to avoid clobbering a
        // good catalog value).
        final total = data['total'] as int?;
        if (total != null && total > 0) {
          unawaited(_db.setChapterPageCount(id, total));
        }
      case 'page':
        unawaited(_db.into(_db.offlinePages).insertOnConflictUpdate(
              OfflinePagesCompanion.insert(
                chapterId: data['chapterId'] as int,
                pageIndex: data['pageIndex'] as int,
                relativePath: data['relPath'] as String,
              ),
            ));
      case 'chapterDone':
        unawaited(_onChapterDone(data));
      case 'drained':
        unawaited(_onDrained());
    }
  }

  /// The worker drained its queue and is self-stopping. Anything enqueued during
  /// that shutdown window is in drift `queued` but stranded in the dying worker
  /// (the "tap download, nothing happens until reopen" bug). So: wait for the
  /// service to actually stop (stopService is async), then re-check the catalog
  /// and restart if work remains. ensureServiceRunning is idempotent.
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
      // Foreground live UI: apply the terminal state immediately (the durable
      // log is still the source of truth and is reconciled on the next replay).
      switch (status) {
        case 'downloaded':
          final ch = await _db.chapterById(chapterId);
          if (ch != null && ch.deviceState != OfflineDeviceState.none) {
            final bytes = await _store.chapterBytes(ch.mangaId, chapterId);
            await _db.setChapterDeviceState(
                chapterId, OfflineDeviceState.downloaded,
                bytes: bytes, downloadedAt: DateTime.now());
          }
        case 'error':
        case 'authFailed':
          await _db.setChapterDeviceState(chapterId, OfflineDeviceState.error);
        // 'offline' / null: leave `downloading` so it resumes.
      }
    }

    // Drain handshake: if the worker just self-stopped (queue empty), do the
    // post-stop reconciliation + a drift requery in case work was enqueued
    // during the async stop window (CRITICAL-1).
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
      accessToken: creds?.uiAccessToken,
      refreshToken: creds?.uiRefreshToken,
      basicCredential: basicToken,
      simpleCookie: creds?.simpleLoginCookie,
    );
  }

  /// After the worker stops, copy any rotated ui_login tokens it persisted back
  /// into the app's [AuthCredentialsStore], then clear the FFT auth keys so a
  /// stale token snapshot never lingers in plugin storage.
  Future<void> _wipeWorkOrderAuth() async {
    final raw =
        await FlutterForegroundTask.getData<String>(key: kTokenRecordKey);
    if (raw != null) {
      try {
        final record = BackgroundTokenRecord.fromJson(
            jsonDecode(raw) as Map<String, Object?>);
        // gen > 0 means the worker rotated the token at least once.
        if (record.gen > 0 &&
            record.authType == 'uiLogin' &&
            record.accessToken != null) {
          final store = _ref.read(authCredentialsStoreProvider.notifier);
          if (record.refreshToken != null) {
            await store.saveUiLoginTokens(
              accessToken: record.accessToken!,
              refreshToken: record.refreshToken!,
            );
          } else {
            await store.updateUiLoginAccessToken(record.accessToken!);
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

  /// True when the active connection is metered (no Wi-Fi and no ethernet).
  /// `connectivity_plus` returns a list; an empty/none list is treated as
  /// metered-ish (no usable unmetered link), so we don't start a wifi-only batch.
  Future<bool> _isMetered() async {
    final result = await Connectivity().checkConnectivity();
    final hasUnmetered = result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
    return !hasUnmetered;
  }

  /// React to connectivity changes while the app is alive: if Wi-Fi-only is on
  /// and we drop to metered, stop the running service (the chapters stay
  /// `downloading` and resume on Wi-Fi). If we (re)gain Wi-Fi and there's
  /// pending work, start it.
  ///
  /// v1 LIMITATION: a Wi-Fi→mobile switch that happens ENTIRELY while the app is
  /// backgrounded isn't caught here (no listener runs) — it's only reconciled on
  /// the next foreground/launch. The worker carries the wifiOnly flag for a
  /// future in-worker gate but does not act on connection type today.
  void _onConnectivityChanged(List<ConnectivityResult> result) {
    if (!Platform.isAndroid) return;
    final wifiOnly = _ref.read(offlineWifiOnlyProvider) ?? true;
    if (!wifiOnly) return;
    final hasUnmetered = result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
    unawaited(() async {
      if (!hasUnmetered) {
        if (await FlutterForegroundTask.isRunningService) {
          logger
              .i('Offline: dropped to metered with Wi-Fi-only — stopping FGS');
          await FlutterForegroundTask.stopService();
        }
      } else {
        // Back on an unmetered link — resume any pending work.
        final pending = await _pendingChapters();
        if (pending.isNotEmpty) await ensureServiceRunning();
      }
    }());
  }

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  /// Request POST_NOTIFICATIONS (Android 13+) before starting the service —
  /// `startService` fails without it. Best-effort: a denial is logged; the start
  /// attempt still proceeds (the OS will simply suppress the notification).
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

  /// A [TokenBroker] backed by FFT storage for the main side, sharing the same
  /// gen-versioned record the worker uses. Provided for callers/tests that need
  /// to coordinate a refresh from the main isolate against the worker's record.
  /// Only ui_login refreshes; the network refresh is delegated to [refreshFn].
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

/// App-lifetime singleton driving the foreground-service downloads on Android.
/// Read it at launch (to `register()` + replay) and from the enqueue/delete
/// sites. Self-gates to Android; a no-op on iOS/desktop (main-isolate pump used
/// there). On web this file is never compiled — the conditional-import shim
/// (`background_download_controller_shim.dart`) swaps in a no-op stub.
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
