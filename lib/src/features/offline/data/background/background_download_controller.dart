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
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/logger/logger.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../auth/data/auth_credentials_store.dart';
import '../../../notifications/controller/notification_settings_providers.dart';
import '../../../notifications/data/local_notification_service.dart';
import '../../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../chapter_commit.dart';
import '../offline_database.dart';
import '../offline_download_progress.dart';
import '../offline_page_store.dart';
import '../offline_paths.dart';
import '../offline_repository.dart';
import '../offline_settings_providers.dart';
import '../server_reachability.dart';
import 'background_completion_log.dart';
import 'background_download_lock.dart';
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

  /// Backoff after the worker parks on an unreachable server. The stop
  /// handshake sees the queue still pending and restarts immediately, which
  /// measured 10 service starts — each booting a background isolate — in 60s
  /// against a dead server.
  DateTime? _parkedUntil;
  Duration _parkBackoff = _minParkBackoff;
  Timer? _parkTimer;

  /// Bumped on every park so a slow chapter commit can tell whether the server
  /// it proved reachable is the one currently parked, or one from before.
  int _parkEpoch = 0;
  static const _minParkBackoff = Duration(seconds: 15);
  static const _maxParkBackoff = Duration(minutes: 5);

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
    _connSub ??= Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
  }

  void dispose() {
    _parkTimer?.cancel();
    // Mirrors register(): off Android nothing was ever wired up, and touching
    // WidgetsBinding here would fault a container-only test with no binding.
    if (!Platform.isAndroid) return;
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
  /// [force] is for signals that supersede the park backoff: an explicit user
  /// action, or proof the server answered.
  Future<void> ensureServiceRunning({bool force = false}) async {
    if (!Platform.isAndroid) return;
    if (_suppressRestarts) return;
    // PAUSE GATE — first line so every restart path (start, onEnqueued,
    // replayOnResume, launch replay, drain/stop handlers, connectivity-resume)
    // inherits it.
    if (_isPaused()) return;
    if (force) {
      _clearPark();
    } else if (_parkedUntil?.isAfter(DateTime.now()) ?? false) {
      return;
    }
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
        // Explicit monochrome icon: the fallback is the launcher icon, which
        // Android alpha-masks into an unrecognizable blob in the status bar.
        notificationIcon: const NotificationIcon(
          metaDataName: kNotificationIconMetaData,
        ),
        callback: backgroundDownloadCallback,
      );
      if (res is ServiceRequestFailure) {
        logger.e('Offline: foreground service failed to start: ${res.error}');
        // Previously silent: chapters stayed queued in drift with nothing
        // downloading and no signal at all (e.g. notification permission
        // denied). A toast is a best-effort surface only — it's a no-op
        // when there's no active UI (background launch/replay), which still
        // leaves that path silent; making it durably visible there needs a
        // persisted banner, not attempted here.
        _ref.read(toastProvider)?.showError(
          'Downloads paused: couldn\'t start the download service '
          '(${res.error})',
        );
      }
    } finally {
      _ensuring = false;
    }
  }

  /// drift is queue authority: queued + (resumable) downloading chapters.
  Future<List<OfflineChapter>> _pendingChapters() async {
    final queued = await _db.chaptersInState(OfflineDeviceState.queued);
    final downloading = await _db.chaptersInState(
      OfflineDeviceState.downloading,
    );
    return [...queued, ...downloading];
  }

  // ---------------------------------------------------------------------------
  // Enqueue / remove / wifi-only changes
  // ---------------------------------------------------------------------------

  /// Called after the caller has written drift `queued` for [chapterIds]. Just
  /// ensures the service owns the queue (it reads drift, not the argument).
  Future<void> onEnqueued(List<int> chapterIds) =>
      requestStart(userInitiated: true);

  /// Something outside the controller wants downloads moving. A user action
  /// outranks the park backoff outright; an automated pass only brings the next
  /// attempt forward, so a trigger that repeats can't defeat it.
  Future<void> requestStart({bool userInitiated = false}) {
    if (!userInitiated) _retrySooner();
    return ensureServiceRunning(force: userInitiated);
  }

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
  Future<void> resume() => ensureServiceRunning(force: true);

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
      FlutterForegroundTask.sendDataToTask({
        'op': 'remove',
        'chapterId': chapterId,
      });
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
      FlutterForegroundTask.sendDataToTask({
        'op': 'setWifiOnly',
        'value': value,
      });
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
    await maybeStartAfterReplay();
  }

  /// Replay only — split out so launch can order it BEFORE the reconcile pass
  /// (which must see post-replay device state), keeping the service start after.
  Future<void> replayAtLaunch() async {
    if (!Platform.isAndroid) return;
    await _replay();
  }

  Future<void> maybeStartAfterReplay() async {
    if (!Platform.isAndroid) return;
    final pending = await _pendingChapters();
    if (pending.isNotEmpty) await ensureServiceRunning();
  }

  Future<void> _replay() async {
    // Replay parses then TRUNCATES — it must own the log. A running worker
    // (FGS or WorkManager catch-up) is asked to yield and checkpoints within
    // seconds; launch never waits out a multi-minute run.
    final lock = BackgroundDownloadLock(File('${_paths.baseDir}/.bg_lock'));
    var acquired = await lock.acquire('replay');
    if (!acquired) {
      await lock.requestYield();
      for (var i = 0; i < 15 && !acquired; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        acquired = await lock.acquire('replay');
      }
    }
    if (!acquired) return; // contended past the wait — next launch replays
    try {
      await replayCompletionLog(
        db: _db,
        store: _store,
        log: _log,
        // Gates catch-up adoptions: a record from another server's catalog is
        // refused (and its files cleaned up), never adopted across identities.
        catalogServerId: _ref
            .read(sharedPreferencesProvider)
            .getString(DBKeys.offlineCatalogServerId.name),
      );
    } finally {
      await lock.release();
    }
  }

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
        unawaited(
          _applyChapterStart(
            data['chapterId'] as int,
            data['total'] as int?,
            data['gen'] as int? ?? 0,
          ),
        );
      case 'page':
        unawaited(_applyPageEvent(data));
      case 'chapterDone':
        unawaited(_onChapterDone(data));
      case 'drained':
        unawaited(_onDrained());
      case 'parked':
        _onParked();
    }
  }

  /// The worker gave up on an unreachable server and stopped with the queue
  /// intact.
  void _onParked() {
    if (_parkedUntil?.isAfter(DateTime.now()) ?? false) return;
    final delay = _nextBackoff();
    _armPark(delay);
    logger.i('Offline: server unreachable — downloads parked for $delay');
    // Lets the reconnect listener resume us as soon as anything else in the app
    // reaches the server, instead of waiting out the backoff.
    _ref.read(serverUnreachableProvider.notifier).set(true);
    // Only on the first park of a run: the service took its own notification
    // with it when it stopped, so without this the queue just goes quiet.
    if (delay == _minParkBackoff) unawaited(_notifyPaused(_PauseReason.server));
  }

  /// The delay to wait now, doubling what the next one will be.
  Duration _nextBackoff() {
    final delay = _parkBackoff;
    _parkBackoff = delay * 2 > _maxParkBackoff ? _maxParkBackoff : delay * 2;
    return delay;
  }

  void _armPark(Duration delay) {
    // Every arming invalidates in-flight completions: a commit that started
    // before the park would otherwise finish, see its captured epoch as
    // current, and clear a park armed while it was running.
    _parkEpoch++;
    _parkedUntil = DateTime.now().add(delay);
    _parkTimer?.cancel();
    _parkTimer = Timer(delay, () => unawaited(_onParkExpired()));
  }

  Future<void> _onParkExpired() async {
    _parkedUntil = null;
    await ensureServiceRunning();
    // The start can decline — Android refusing the service, Wi-Fi-only holding
    // it back — and the deadline is gone by then, so without re-arming here the
    // queue would sit with nothing left to wake it.
    if (_parkedUntil != null) return;
    if (await FlutterForegroundTask.isRunningService) return;
    if ((await _pendingChapters()).isEmpty) return;
    _armPark(_nextBackoff());
  }

  void _clearPark() {
    _parkTimer?.cancel();
    _parkTimer = null;
    _parkedUntil = null;
    _parkBackoff = _minParkBackoff;
  }

  /// Bring the next attempt forward for a signal that suggests the server may
  /// be back but doesn't prove it. Never nearer than the minimum, so a link
  /// flapping every few seconds can't restart the service every few seconds.
  void _retrySooner() {
    final until = _parkedUntil;
    if (until == null) return;
    if (until.difference(DateTime.now()) > _minParkBackoff) {
      _armPark(_minParkBackoff);
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

  /// A page landed in the worker's staging area. Nothing is written to the
  /// catalog — the chapter isn't published until it commits — so this only
  /// moves the progress arc.
  Future<void> _applyPageEvent(Map data) async {
    final total = data['total'] as int? ?? 0;
    if (total <= 0) return;
    final id = data['chapterId'] as int;
    // Same staleness guard as chapterStart and the terminal apply: an event
    // already in the port when a delete lands must not re-enter the map for a
    // chapter that no longer exists.
    final c = await _db.chapterById(id);
    if (c == null || c.deviceState == OfflineDeviceState.none) return;
    if ((data['gen'] as int? ?? 0) < c.downloadGeneration) return;
    _ref
        .read(offlineDownloadProgressProvider.notifier)
        .start(id, total: total, done: data['done'] as int? ?? 0);
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
    if (pending.isNotEmpty) {
      await ensureServiceRunning();
      return;
    }
    await _notifyDownloadsComplete();
  }

  /// Chapters that finished / failed this download session — drive the
  /// completion + error notifications once the queue truly drains.
  int _sessionDownloaded = 0;
  int _sessionFailed = 0;

  /// Fire the completion + error notifications on drain (opt-in). Only covers a
  /// download session THIS device ran — a server/WebUI download with the app
  /// closed has no observer here.
  Future<void> _notifyDownloadsComplete() async {
    final done = _sessionDownloaded;
    final failed = _sessionFailed;
    _sessionDownloaded = 0;
    _sessionFailed = 0;
    if (done == 0 && failed == 0) return;
    if (!_ref.read(notificationsDownloadsEnabledProvider).ifNull(true)) return;
    try {
      final locales = WidgetsBinding.instance.platformDispatcher.locales;
      final l10n = lookupAppLocalizations(
        locales.isNotEmpty ? locales.first : const Locale('en'),
      );
      final service = LocalNotificationService();
      await service.init();
      if (done > 0) {
        await service.showDownloadsComplete(
          title: l10n.notificationDownloadsCompleteTitle,
          body: l10n.notificationDownloadsCompleteBody(done),
        );
      }
      if (failed > 0) {
        await service.showDownloadError(
          l10n.notificationDownloadErrorTitle,
          l10n.notificationDownloadErrorBody(failed),
        );
      }
    } catch (_) {
      // Best-effort — a missed toast is not data loss.
    }
  }

  /// Says why the queue stopped: the service owns the download notification,
  /// so stopping it takes the only on-screen explanation with it.
  Future<void> _notifyPaused(_PauseReason reason) async {
    if (!_ref.read(notificationsDownloadsEnabledProvider).ifNull(true)) return;
    try {
      final locales = WidgetsBinding.instance.platformDispatcher.locales;
      final l10n = lookupAppLocalizations(
        locales.isNotEmpty ? locales.first : const Locale('en'),
      );
      final service = LocalNotificationService();
      await service.init();
      await service.showDownloadError(
        l10n.notificationDownloadsPausedTitle,
        switch (reason) {
          _PauseReason.wifi => l10n.notificationDownloadsPausedWifi,
          _PauseReason.server => l10n.notificationDownloadsPausedNoServer,
        },
      );
    } catch (_) {
      // Best-effort — a missed notification is not data loss.
    }
  }

  Future<void> _onChapterDone(Map data) async {
    final chapterId = data['chapterId'] as int?;
    final status = data['status'] as String?;
    // Ahead of the awaits below: this event races the worker's `parked` message,
    // and the stop handshake at the end of this method would otherwise restart
    // the service before the latch is set.
    if (status == 'offline') _onParked();
    final epoch = _parkEpoch;
    // Outside the status guard: a cancel (pause, delete, Wi-Fi drop) reports a
    // null status, and leaving those entries behind grows the map for the life
    // of the process and shows a re-queued chapter the last attempt's percent.
    if (chapterId != null) {
      _ref.read(offlineDownloadProgressProvider.notifier).clear(chapterId);
    }
    if (chapterId != null && status != null) {
      // SINGLE COMMITTER: the worker only fills staging. Publishing the chapter
      // happens here, on the main isolate, so exactly one party ever renames a
      // staging directory into place and writes the rows for it.
      if (status == 'downloaded') {
        final ch = await _db.chapterById(chapterId);
        final result = ch == null
            ? ChapterCommitResult.refused
            : await commitStagedChapter(
                db: _db,
                store: _store,
                mangaId: ch.mangaId,
                chapterId: chapterId,
              );
        // The worker saying "done" isn't the same as the chapter landing: a
        // stale event, a delete, or short staging all end here without
        // publishing anything, and counting those would have the completion
        // notification claim chapters the user doesn't have.
        if (result == ChapterCommitResult.committed) {
          _sessionDownloaded++;
          // A chapter landed, so the server is demonstrably fine — unless a
          // later chapter parked while this one was committing.
          if (_parkEpoch == epoch) _clearPark();
        }
      } else {
        await applyBackgroundTerminalState(
          db: _db,
          chapterId: chapterId,
          status: status,
          eventGeneration: data['gen'] as int? ?? 0,
        );
        if (status == 'error') _sessionFailed++;
      }
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
      key: kWorkOrderKey,
      value: jsonEncode(order.toJson()),
    );
    // Seed the shared token record so the worker's broker reads/writes the same
    // gen-versioned record we'll read back on stop.
    await FlutterForegroundTask.saveData(
      key: kTokenRecordKey,
      value: jsonEncode(auth.toJson()),
    );
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
    final raw = await FlutterForegroundTask.getData<String>(
      key: kTokenRecordKey,
    );
    if (raw != null) {
      try {
        final record = BackgroundTokenRecord.fromJson(
          jsonDecode(raw) as Map<String, Object?>,
        );
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
            await store.updateUiLoginAccessToken(
              record.accessToken!,
              forEpoch: epoch,
            );
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
    final hasUnmetered =
        result.contains(ConnectivityResult.wifi) ||
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
    final hasUnmetered =
        result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
    final hasConnection =
        result.any((r) => r != ConnectivityResult.none) && result.isNotEmpty;
    unawaited(() async {
      if (wifiOnly && !hasUnmetered) {
        // Wi-Fi-only and dropped to metered: stop the running service (chapters
        // stay `downloading` and resume on Wi-Fi).
        if (await FlutterForegroundTask.isRunningService) {
          logger.i(
            'Offline: dropped to metered with Wi-Fi-only — stopping FGS',
          );
          await FlutterForegroundTask.stopService();
          await _notifyPaused(_PauseReason.wifi);
        }
        return;
      }
      // Only the Wi-Fi-only case used to stop the service, so with that off
      // the worker kept running against a network that was gone.
      if (!hasConnection) {
        if (await FlutterForegroundTask.isRunningService) {
          logger.i('Offline: no connection — stopping FGS');
          // Before the stop: the cancelled chapter's terminal event runs the
          // restart handshake, which would put a fresh worker straight back on
          // a network that isn't there.
          _armPark(_nextBackoff());
          await FlutterForegroundTask.stopService();
          await _notifyPaused(_PauseReason.server);
        }
        return;
      }
      // A usable link returned — resume pending work; covers a queue parked by
      // a resolve-time network drop that would otherwise strand until app
      // resume.
      final pending = await _pendingChapters();
      if (pending.isEmpty) return;
      _retrySooner();
      await ensureServiceRunning();
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
  }) => TokenBroker(
    read: () async {
      final raw = await FlutterForegroundTask.getData<String>(
        key: kTokenRecordKey,
      );
      if (raw != null) {
        return BackgroundTokenRecord.fromJson(
          jsonDecode(raw) as Map<String, Object?>,
        );
      }
      return _snapshotAuth();
    },
    write: (r) => FlutterForegroundTask.saveData(
      key: kTokenRecordKey,
      value: jsonEncode(r.toJson()),
    ),
    refreshFn: refreshFn,
  );
}

/// App-lifetime singleton driving the foreground-service downloads on
/// Android; read at launch (register + replay) and from enqueue/delete sites.
/// No-op on iOS/desktop; on web this file isn't compiled at all —
/// `background_download_controller_shim.dart` swaps in a stub.
final backgroundDownloadControllerProvider =
    Provider<BackgroundDownloadController>((Ref ref) {
      final controller = BackgroundDownloadController(ref);
      // App-lifetime in practice, but a container teardown (tests, a full
      // reset) must not leave its retry timer and listeners running against a
      // disposed Ref.
      ref.onDispose(controller.dispose);
      return controller;
    });

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

/// Why on-device downloads stopped, for the notification that stands in for the
/// foreground service's own once it has been torn down.
enum _PauseReason { wifi, server }
