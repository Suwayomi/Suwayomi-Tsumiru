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
import '../../../../utils/crash/diagnostics.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/logger/logger.dart';
import '../../../auth/data/auth_credentials_store.dart';
import '../../../auth/data/custom_headers_store.dart';
import '../../../notifications/controller/notification_settings_providers.dart';
import '../../../notifications/controller/notifications_controller.dart';
import '../../../notifications/data/local_notification_service.dart';
import '../../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../chapter_commit.dart';
import '../offline_database.dart';
import '../offline_download_progress.dart';
import '../offline_download_stall.dart';
import '../offline_page_store.dart';
import '../offline_paths.dart';
import '../offline_repository.dart';
import '../offline_server_identity_repository.dart';
import '../offline_settings_providers.dart';
import '../server_reachability.dart';
import 'background_completion_log.dart';
import 'background_download_lock.dart';
import 'background_schedule.dart';
import 'background_token_record.dart';
import 'background_work_order.dart';
import 'catchup_spec_writer.dart';
import 'catchup_work_spec.dart';
import 'download_task_handler.dart';
import 'foreground_service_gateway.dart';
import 'work_order_admission.dart';

/// Owns the Android foreground-service download worker from the MAIN isolate —
/// starts/stops it, mirrors drift into it, and applies its events + completion
/// log back into drift. Single-owner invariant: exactly one isolate downloads
/// while the queue is non-empty on Android, so the main-isolate pump must never
/// run there; on other platforms this controller is a no-op and the
/// main-isolate pump is used instead.
class BackgroundDownloadController with WidgetsBindingObserver {
  BackgroundDownloadController(
    this._ref, {
    ForegroundServiceGateway? gateway,
    bool Function()? isAndroid,
    Future<List<ConnectivityResult>> Function()? connectivity,
    Stream<List<ConnectivityResult>>? connectivityChanges,
    Future<void> Function(String? reason, {required bool silent})? notifyStall,
    Future<void> Function()? publishQueue,
    bool Function()? identityAllowed,
    DateTime Function()? now,
    Timer Function(Duration, void Function())? timer,
  }) : _gateway = gateway ?? ForegroundServiceGateway(),
       _isAndroid = isAndroid ?? (() => Platform.isAndroid),
       _connectivity = connectivity ?? Connectivity().checkConnectivity,
       _connectivityChanges =
           connectivityChanges ?? Connectivity().onConnectivityChanged,
       _notifyStallOverride = notifyStall,
       _publishQueueOverride = publishQueue,
       _identityAllowedOverride = identityAllowed,
       _now = now ?? DateTime.now,
       _timer = timer ?? Timer.new;

  final ForegroundServiceGateway _gateway;
  final bool Function() _isAndroid;
  final Future<List<ConnectivityResult>> Function() _connectivity;
  final Stream<List<ConnectivityResult>> _connectivityChanges;
  final Future<void> Function(String?, {required bool silent})?
  _notifyStallOverride;
  final Future<void> Function()? _publishQueueOverride;
  final bool Function()? _identityAllowedOverride;
  final DateTime Function() _now;

  bool get _identityAllowed =>
      _identityAllowedOverride?.call() ??
      (_ref.read(offlineActiveProvider) &&
          CatchupStateStore(
            _ref.read(sharedPreferencesProvider),
          ).identityAuthorized);
  final Timer Function(Duration, void Function()) _timer;
  int _recoveryEpoch = 0;
  Future<void> _identityTail = Future.value();
  Future<void> _mutationTail = Future.value();
  DateTime? _lastRecovery;
  AppLifecycleState? _lastLifecycle;
  bool? _retryBlocked;
  bool _disposed = false;
  String? _notifiedStall;
  bool _hasNotifiedStall = false;
  String? _pendingSignature;
  Timer? _queuePublishTimer;
  Future<void>? _queuePublishFlight;
  bool _queuePublishPending = false;
  Timer? _handoffTimer;
  bool _yieldedService = false;
  bool _handoffForce = false;
  int _restrictionEpoch = 0;
  Future<void> _notificationTail = Future.value();
  StreamSubscription<List<OfflineChapter>>? _pendingSub;

  bool get _blocked =>
      _retryBlocked ??= _ref.read(offlineDownloadsStalledProvider) != null;

  void _allowRecovery() {
    _recoveryEpoch++;
    _lastRecovery = _now();
    _retryBlocked = false;
  }

  Future<void> _clearStall() async {
    _restrictionEpoch++;
    _retryBlocked = false;
    await _ref.read(offlineDownloadsStalledProvider.notifier).set(null);
    _ref.read(offlineDownloadRestrictionProvider.notifier).set(null);
    await _publishStall(null);
  }

  Future<void> _clearServiceStall() async {
    _retryBlocked = false;
    await _ref.read(offlineDownloadsStalledProvider.notifier).set(null);
    await _refreshRestriction();
  }

  Future<void> _publishStall(String? reason) {
    final next = _notificationTail.then((_) => _deliverStall(reason));
    _notificationTail = next.catchError((Object _) {});
    return next;
  }

  Future<void> _deliverStall(String? reason) async {
    if (_isPaused() || _suppressRestarts) reason = null;
    if (_hasNotifiedStall && reason == _notifiedStall) return;
    final silent = _notifiedStall != null;
    _notifiedStall = reason;
    _hasNotifiedStall = true;
    if (_notifyStallOverride != null) {
      await _notifyStallOverride(reason, silent: silent);
      return;
    }
    try {
      final service = LocalNotificationService();
      await service.init();
      if (reason == null) {
        await service.cancelDownloadStall();
        return;
      }
      if (!_ref.read(notificationsDownloadsEnabledProvider).ifNull(true)) {
        return;
      }
      final locales = WidgetsBinding.instance.platformDispatcher.locales;
      final l10n = lookupAppLocalizations(
        locales.isNotEmpty ? locales.first : const Locale('en'),
      );
      await service.showDownloadStall(
        l10n.notificationDownloadsPausedTitle,
        switch (reason) {
          'wifi' => l10n.notificationDownloadsPausedWifi,
          'connection' => l10n.notificationDownloadsPausedNoServer,
          'background' => l10n.notificationDownloadsPausedBackground,
          'budget' => l10n.notificationDownloadsPausedBudget,
          _ => l10n.notificationDownloadsPausedService,
        },
        silent: silent,
      );
    } catch (error) {
      logger.w('Offline: download stall notification failed: $error');
    }
  }

  Future<bool> _refreshRestriction() async {
    final epoch = ++_restrictionEpoch;
    if (_isPaused() ||
        _suppressRestarts ||
        (await _pendingChapters()).isEmpty) {
      await _clearStall();
      return true;
    }
    final connections = await _connectivity();
    final pending = await _pendingChapters();
    if (epoch != _restrictionEpoch) return true;
    if (_isPaused() || _suppressRestarts || pending.isEmpty) {
      await _clearStall();
      return true;
    }
    final connected = connections.any((r) => r != ConnectivityResult.none);
    final unmetered =
        connections.contains(ConnectivityResult.wifi) ||
        connections.contains(ConnectivityResult.ethernet);
    final networkReason = !connected
        ? 'connection'
        : ((_ref.read(offlineWifiOnlyProvider) ?? true) && !unmetered)
        ? 'wifi'
        : null;
    final reason =
        networkReason ??
        (_ref.read(serverUnreachableProvider) ? 'connection' : null);
    _ref.read(offlineDownloadRestrictionProvider.notifier).set(reason);
    final stalled = _ref.read(offlineDownloadsStalledProvider);
    await _publishStall(reason ?? stalled);
    return networkReason != null;
  }

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
  int _controlCount = 0;
  final Object _controlZone = Object();

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
  Future<void> _recoverIdentityTransition() async {
    final state = CatchupStateStore(_ref.read(sharedPreferencesProvider));
    if (!_suppressRestarts && state.identityChanging) {
      await state.setIdentityChanging(false);
      _ref.invalidate(serverInstanceIdProvider);
    }
  }

  void register() {
    if (!_isAndroid()) return;
    _notifiedStall ??= _ref.read(offlineDownloadsStalledProvider);
    unawaited(_recoverIdentityTransition());
    WidgetsBinding.instance.addObserver(this);
    _workerEventCallback ??= _onWorkerEvent;
    _gateway.addCallback(_workerEventCallback!);
    _pendingSub ??= _db.watchOfflineChapters().listen((chapters) {
      final pending = [
        for (final c in chapters)
          if (c.deviceState == OfflineDeviceState.queued ||
              c.deviceState == OfflineDeviceState.downloading)
            '${c.mangaId}:${c.id}:${c.downloadGeneration}',
      ]..sort();
      final signature = pending.join(',');
      if (signature == _pendingSignature) return;
      _pendingSignature = signature;
      _queuePublishTimer?.cancel();
      _queuePublishTimer = _timer(const Duration(milliseconds: 250), () {
        unawaited(
          _publishQueue().catchError((Object error) {
            logger.e('Offline: publishing download queue failed: $error');
          }),
        );
      });
      if (pending.isEmpty) unawaited(_clearStall());
    });
    _ref.listen(serverInstanceIdProvider, (_, next) {
      if (next.hasValue && _identityAllowed) {
        unawaited(_publishQueue().then((_) => ensureServiceRunning()));
      }
    });
    _ref.listen(offlineWifiOnlyProvider, (_, next) {
      unawaited(onWifiOnlyChanged(next ?? true));
    });
    _ref.listen(serverUnreachableProvider, (_, _) {
      unawaited(_refreshRestriction());
    });
    _connSub ??= _connectivityChanges.listen(_onConnectivityChanged);
  }

  void dispose() {
    _disposed = true;
    _queuePublishTimer?.cancel();
    _handoffTimer?.cancel();
    unawaited(_pendingSub?.cancel());
    _parkTimer?.cancel();
    // Mirrors register(): off Android nothing was ever wired up, and touching
    // WidgetsBinding here would fault a container-only test with no binding.
    if (!_isAndroid()) return;
    WidgetsBinding.instance.removeObserver(this);
    final cb = _workerEventCallback;
    if (cb != null) _gateway.removeCallback(cb);
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
    if (force && _controlCount > 0) _handoffForce = true;
    if (!_isAndroid() ||
        _disposed ||
        _suppressRestarts ||
        _controlCount > 0 ||
        !_identityAllowed) {
      return;
    }
    if (_isPaused()) {
      await _clearStall();
      return;
    }
    if (_ensuring) {
      if (force) _scheduleHandoff(force: true);
      return;
    }
    _ensuring = true;
    final epoch = _recoveryEpoch;
    try {
      final pending = await _pendingChapters();
      if (pending.isEmpty) {
        await _clearStall();
        return;
      }
      final restricted = await _refreshRestriction();
      if (_isPaused() || _suppressRestarts) {
        await _clearStall();
        return;
      }
      final running = await _gateway.isRunningService;
      if (_controlCount > 0 || _isPaused() || _suppressRestarts) return;
      if (_yieldedService) {
        if (running) {
          _scheduleHandoff(force: force);
          return;
        }
        _yieldedService = false;
      }
      if (running) {
        for (final c in pending) {
          _gateway.send({
            'op': 'add',
            'chapterId': c.id,
            'mangaId': c.mangaId,
            'gen': _genOf(c),
          });
        }
        await _clearServiceStall();
        return;
      }
      if (restricted || _blocked) return;
      if (force) _clearPark();
      if (_parkedUntil?.isAfter(_now()) ?? false) return;
      await _gateway.ensureNotificationPermission();
      if (_controlCount > 0 || _isPaused() || _suppressRestarts) return;
      final attemptId = await _writeWorkOrder();
      if (attemptId == null) return;
      if (_isPaused() || _suppressRestarts || _controlCount > 0) {
        await _invalidateAttempt(attemptId);
        await _clearStall();
        return;
      }
      final result = await _gateway.start();
      if (_isPaused() || _suppressRestarts || _controlCount > 0) {
        await _invalidateAttempt(attemptId);
        if (await _gateway.isRunningService) _pauseWorker();
        await _clearStall();
        return;
      }
      if (result is ServiceRequestFailure) {
        await withWorkOrderAdmission(_paths.baseDir, () async {
          final accepted = await _gateway.read(kAcceptedWorkOrderKey);
          if (accepted == attemptId) {
            await _clearServiceStall();
            return;
          }
          final current = decodeWorkOrder(await _gateway.read(kWorkOrderKey));
          if (current?.attemptId == attemptId) {
            await _gateway.remove(kWorkOrderKey);
            await _gateway.remove(kTokenRecordKey);
          }
          if (_isPaused() || _suppressRestarts) {
            await _clearStall();
            return;
          }
          logger.e(
            'Offline: foreground service failed to start: ${result.error}',
          );
          _retryBlocked = epoch == _recoveryEpoch;
          final error = result.error.toString();
          final reason =
              error.contains(
                'Time limit already exhausted for foreground service type dataSync',
              )
              ? 'budget'
              : error.contains('ForegroundServiceStartNotAllowedException')
              ? 'background'
              : 'service';
          await _ref.read(offlineDownloadsStalledProvider.notifier).set(reason);
        });
        await _refreshRestriction();
      } else {
        await _clearServiceStall();
      }
    } catch (error) {
      logger.e('Offline: preparing download service failed: $error');
      if (_isPaused() || _suppressRestarts) {
        await _clearStall();
      } else {
        _retryBlocked = epoch == _recoveryEpoch;
        await _ref
            .read(offlineDownloadsStalledProvider.notifier)
            .set('service');
        await _refreshRestriction();
      }
    } finally {
      if (force && _controlCount > 0) _handoffForce = true;
      _ensuring = false;
      if (!_disposed &&
          epoch != _recoveryEpoch &&
          !_isPaused() &&
          !_suppressRestarts) {
        await ensureServiceRunning();
      }
    }
  }

  /// The worker receives its endpoint in a launch-time work order. Restart it
  /// on a LAN/remote handover so queued page GETs never remain pinned to the
  /// address that just became unreachable.
  Future<void> restartForEndpointChange() => ensureServiceRunning(force: true);

  Future<T> changeIdentity<T>(Future<T> Function() action) async {
    if (Zone.current[_controlZone] == this) return action();
    return _ref
        .read(authCredentialsStoreProvider.notifier)
        .withIdentityChange(() => _changeIdentityOwned(action));
  }

  Future<T> _changeIdentityOwned<T>(Future<T> Function() action) async {
    if (!_isAndroid() ||
        !_ref.read(offlineEnabledProvider) ||
        Zone.current[_controlZone] == this) {
      return action();
    }
    final previous = _identityTail;
    final finished = Completer<void>();
    _identityTail = finished.future;
    await previous;
    _suppressRestarts = true;
    final state = CatchupStateStore(_ref.read(sharedPreferencesProvider));
    try {
      await state.setIdentityChanging(true);
      await state.setIdentityAuthorized(false);
      return await withOwnership(() async {
        await withWorkOrderAdmission(_paths.baseDir, () async {
          await _gateway.remove(kWorkOrderKey);
          await _gateway.remove(kTokenRecordKey);
        });
        await withBackgroundScheduleLock(
          state.clearState,
          baseDir: _paths.baseDir,
        );
        await _clearStall();
        final result = await action();
        await state.setIdentityChanging(false);
        _ref.invalidate(serverInstanceIdProvider);
        return result;
      });
    } finally {
      try {
        await state.setIdentityChanging(false);
        await reconcileBackgroundSchedule();
      } finally {
        _suppressRestarts = false;
        finished.complete();
      }
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
    if (userInitiated) {
      _allowRecovery();
      if (_controlCount > 0) _handoffForce = true;
    }
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
    if (!_isAndroid()) return;
    await _clearStall();
    await withWorkOrderAdmission(_paths.baseDir, () async {
      final order = decodeWorkOrder(await _gateway.read(kWorkOrderKey));
      final accepted = await _gateway.read(kAcceptedWorkOrderKey);
      if (order != null && order.attemptId != accepted) {
        await _gateway.remove(kTokenRecordKey);
      }
      await _gateway.remove(kWorkOrderKey);
    });
    if (await _gateway.isRunningService) {
      // Graceful: the worker cancels + self-stops. Never main-side stopService
      // here — it would race the worker and could corrupt a half-written page.
      _pauseWorker();
    }
    await withOwnership(() async {});
  }

  Future<void> _publishQueue() {
    _queuePublishPending = true;
    return _queuePublishFlight ??= _flushQueue();
  }

  Future<void> _flushQueue() async {
    try {
      do {
        _queuePublishPending = false;
        if (_disposed) return;
        try {
          await _writeQueueSnapshot();
        } catch (_) {
          if (!_queuePublishPending) rethrow;
        }
      } while (_queuePublishPending);
    } finally {
      _queuePublishFlight = null;
    }
  }

  Future<void> _writeQueueSnapshot() async {
    if (_publishQueueOverride != null) return _publishQueueOverride();
    if (!_isAndroid() || !_ref.read(offlineEnabledProvider)) return;
    await writeCatchupWorkSpec(_ref.read);
    await _ref.read(notificationsControllerProvider).sync();
  }

  Future<T> withOwnership<T>(Future<T> Function() action) async {
    if (!_isAndroid() || Zone.current[_controlZone] == this) return action();
    final lock = BackgroundDownloadLock(File('${_paths.baseDir}/.bg_lock'));
    _controlCount++;
    try {
      var acquired = await lock.acquire('control');
      if (!acquired) {
        await lock.requestYield();
        if (await _gateway.isRunningService) _pauseWorker();
      }
      for (var i = 0; !acquired && i < 300; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        acquired = await lock.acquire('control');
        if (!acquired) await lock.requestYield();
      }
      if (!acquired) {
        throw StateError('Downloads did not stop; action remains pending');
      }
      await _mutationTail;
      return await runZoned(() async {
        final result = await action();
        await _publishQueue();
        return result;
      }, zoneValues: {_controlZone: this});
    } finally {
      await lock.release();
      _controlCount--;
      if (_controlCount == 0 &&
          !_isPaused() &&
          !_suppressRestarts &&
          !_blocked) {
        _scheduleHandoff();
      }
    }
  }

  void _pauseWorker() {
    _yieldedService = true;
    _gateway.send({'op': 'pause'});
  }

  void _scheduleHandoff({bool force = false}) {
    if (_disposed || _isPaused() || _suppressRestarts || _blocked) return;
    _handoffForce |= force;
    _handoffTimer?.cancel();
    _handoffTimer = _timer(const Duration(milliseconds: 500), () {
      if (_ensuring || _controlCount > 0) {
        _scheduleHandoff();
        return;
      }
      final force = _handoffForce;
      _handoffForce = false;
      if (!_disposed) unawaited(ensureServiceRunning(force: force));
    });
  }

  /// Resume on-device downloads (caller has cleared the persisted flag first).
  Future<void> resume() => requestStart(userInitiated: true);

  Future<void> stopAndClearWorkOrder() async {
    if (!_isAndroid()) return;
    _suppressRestarts = true;
    await pause();
    if (await _gateway.isRunningService) {
      await _gateway.stop();
    }
    for (var i = 0; i < 20; i++) {
      if (!await _gateway.isRunningService) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await _gateway.remove(kWorkOrderKey);
    await _gateway.remove(kTokenRecordKey);
    await CatchupStateStore(_ref.read(sharedPreferencesProvider)).clearState();
    final log = _log;
    if (await log.file.exists()) await log.file.delete();
  }

  void finishCatalogClear() {
    _suppressRestarts = false;
  }

  /// Tell the worker to drop a chapter (delete/cancel). The caller still does
  /// the actual drift/file delete; this only stops the in-flight download.
  Future<void> onRemoved(int chapterId) async {
    if (!_isAndroid()) return;
    await withWorkOrderAdmission(_paths.baseDir, () async {
      final raw = await _gateway.read(kWorkOrderKey);
      if (raw == null) return;
      final data = (jsonDecode(raw) as Map).cast<String, Object?>();
      data['chapterIds'] = (data['chapterIds'] as List)
          .where((id) => id != chapterId)
          .toList();
      await _gateway.write(kWorkOrderKey, jsonEncode(data));
    });
    if (await _gateway.isRunningService) {
      _gateway.send({'op': 'remove', 'chapterId': chapterId});
    }
  }

  /// Record a delete tombstone at [newGeneration] (already bumped in drift) so
  /// a stale entry from the previous generation can't complete the chapter
  /// after it's re-queued.
  Future<void> recordChapterDeleted(int chapterId, int newGeneration) async {
    if (!_isAndroid()) return;
    await _log.appendDeleted(chapterId, newGeneration);
  }

  /// Push a Wi-Fi-only setting change to the worker, and enforce it from the
  /// main side: if it's now on + we're metered, stop the running service.
  Future<void> onWifiOnlyChanged(bool value) async {
    if (!_isAndroid()) return;
    try {
      await _publishQueue();
    } catch (error) {
      logger.e('Offline: publishing Wi-Fi policy failed: $error');
    }
    if (_isPaused() || (await _pendingChapters()).isEmpty) {
      await _clearStall();
      return;
    }
    final restricted = await _refreshRestriction();
    if (await _gateway.isRunningService) {
      _gateway.send({'op': 'setWifiOnly', 'value': value});
      if (value && await _isMetered()) {
        await _gateway.stop();
      }
    } else if (!restricted) {
      await requestStart();
    }
  }

  // ---------------------------------------------------------------------------
  // App lifecycle
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isAndroid()) return;
    final previous = _lastLifecycle;
    _lastLifecycle = state;
    if (state == AppLifecycleState.resumed) {
      // Only replay when coming back from a true background state (paused /
      // hidden / detached). Pulling down the notification panel and closing it
      // sends inactive → resumed without ever going to paused — treating that
      // as a resume would re-send add ops for every pending chapter to the FGS,
      // interrupting in-progress downloads unnecessarily.
      final wasBackground = previous == AppLifecycleState.paused ||
          previous == AppLifecycleState.hidden ||
          previous == AppLifecycleState.detached ||
          previous == null; // first resume at launch
      if (!wasBackground) return;
      unawaited(replayOnResume());
    }
    // paused/hidden/detached: NOTHING — the FGS already owns the queue.
  }

  /// Replay the completion log into drift (live-UI catch-up on resume).
  Future<void> replayOnResume() async {
    _allowRecovery();
    _retrySooner();
    await _replay();
    // The FGS may have been killed while backgrounded (OOM, the dataSync time
    // cap, a swipe-away); restart if pending work remains — ensureServiceRunning
    // is idempotent/no-op if the worker's still alive.
    await ensureServiceRunning();
  }

  /// At launch: replay any log left by a previous run, then — if drift still has
  /// a non-empty queue — (re)start the service to finish it.
  Future<void> replayAtLaunchAndMaybeStart() async {
    if (!_isAndroid()) return;
    await _replay();
    await maybeStartAfterReplay();
  }

  /// Replay only — split out so launch can order it BEFORE the reconcile pass
  /// (which must see post-replay device state), keeping the service start after.
  Future<void> replayAtLaunch() async {
    if (!_isAndroid()) return;
    await _replay();
  }

  Future<void> maybeStartAfterReplay() async {
    if (!_isAndroid()) return;
    _allowRecovery();
    _retrySooner();
    await ensureServiceRunning();
  }

  Future<void> _replay() => withOwnership(() async {
    await replayCompletionLog(
      db: _db,
      store: _store,
      log: _log,
      // Gates catch-up adoptions: a record from another server's catalog is
      // refused (and its files cleaned up), never adopted across identities.
      onTimeout: () => _recordTimeout(blockRetry: false),
      catalogServerId: _ref
          .read(sharedPreferencesProvider)
          .getString(DBKeys.offlineCatalogServerId.name),
    );
  });

  // ---------------------------------------------------------------------------
  // Worker events + drain handshake (CRITICAL-1)
  // ---------------------------------------------------------------------------

  void _onWorkerEvent(Object data) {
    if (data is! Map) return;
    // During a catalog clear the worker is being torn down; a page/chapter
    // event still queued in the SendPort would otherwise re-insert a row into
    // the just-wiped catalog — drop everything until the clear releases the flag.
    if (_suppressRestarts || _controlCount > 0) return;
    switch (data['kind']) {
      // Live foreground UI only — mark downloading + accumulate page rows so
      // the progress arc animates; the durable record is the completion log,
      // replayed on resume.
      case 'timedOut':
        final occurred = DateTime.tryParse(data['at'] as String? ?? '');
        unawaited(
          _recordTimeout(
            blockRetry:
                occurred == null ||
                _lastRecovery == null ||
                occurred.isAfter(_lastRecovery!),
          ),
        );
      case 'chapterStart':
        unawaited(
          _runMutation(
            () => _applyChapterStart(
              data['chapterId'] as int,
              data['total'] as int?,
              data['gen'] as int? ?? 0,
            ),
          ),
        );
      case 'page':
        unawaited(_applyPageEvent(data));
      case 'chapterDone':
        unawaited(_onChapterDone(data));
      case 'drained':
        unawaited(_onDrained());
      case 'parked':
        _onParked(
          chapterId: data['chapterId'] as int?,
          mangaId: data['mangaId'] as int?,
          reason: data['reason'] as String?,
        );
      case 'lockFailed':
        if (_controlCount == 0 && !_blocked && !_isPaused()) {
          _armPark(_minParkBackoff);
        }
        recordDiagnostic(
          '[${_now().toIso8601String()}] offline-fgs: '
          'lock-acquire-failed — another party (likely the WorkManager '
          'catch-up executor) still holds .bg_lock; this run stopped without '
          'attempting any chapter\n',
        );
      case 'noWorkOrder':
        recordDiagnostic(
          '[${_now().toIso8601String()}] offline-fgs: '
          'no-work-order starter=${data['starter']} — started with nothing '
          'to do and self-stopped instantly; a run of these with '
          'starter=system means Android itself is repeatedly restarting the '
          'service, not this app\'s own retry logic\n',
        );
    }
  }

  Future<void> _recordTimeout({required bool blockRetry}) async {
    if (_isPaused() ||
        _suppressRestarts ||
        (await _pendingChapters()).isEmpty) {
      return;
    }
    if (blockRetry) _retryBlocked = true;
    await _ref.read(offlineDownloadsStalledProvider.notifier).set('budget');
    await _refreshRestriction();
  }

  /// Consecutive parks attributed to one specific chapter — diagnostics only,
  /// never a give-up signal. A park always means the SERVER could not be
  /// reached for this chapter (see `_downloadChapter`'s null-vs-empty
  /// distinction in download_task_handler.dart, which already routes a
  /// genuine "server answered, no pages" straight to `error` without ever
  /// parking); attributing several in a row to the same chapter just reflects
  /// that it's the head of the queue every backoff cycle, not that its own
  /// source is broken. A previous version marked the chapter `error` after
  /// three, which during a proxy/tunnel outage (backoff runs 15s to 5min)
  /// condemned the queue's head within minutes of a blip that had nothing to
  /// do with that chapter. A chapter whose source really is gone already has
  /// its own persisted give-up path (serverFetchAttempts, see
  /// offline_reconciler.dart), so this counter no longer drives one.
  final Map<int, int> _chapterParkAttempts = {};

  /// How many consecutive commit failures a chapter gets before it is given up
  /// on and marked `error`. Prevents the phantom-download loop where a chapter
  /// whose staging always fails to commit stays `downloading` in drift and is
  /// re-enqueued by `_pendingChapters()` on every `afterDrained` restart.
  static const _maxCommitFailures = 3;
  final Map<int, int> _commitFailures = {};

  /// The worker gave up on an unreachable server and stopped with the queue
  /// intact — OR, just as often in practice, gave up resolving/downloading
  /// one specific chapter whose source is gone (a reverse proxy in front of
  /// the Suwayomi server answers a dead per-chapter source fetch with a
  /// gateway-style status, which reads identically to "the whole server is
  /// down" from here). [chapterId]/[mangaId] are null only for the rare path
  /// that can't attribute the park to one chapter. [reason] is the short
  /// technical detail behind THIS specific attempt (an exception or HTTP
  /// status) — logged every time so a chapter that keeps parking can be
  /// diagnosed, not just seen to be "offline" with no further explanation.
  void _onParked({int? chapterId, int? mangaId, String? reason}) {
    final ts = _now().toIso8601String();
    if (chapterId != null) {
      final attempts = (_chapterParkAttempts[chapterId] ?? 0) + 1;
      _chapterParkAttempts[chapterId] = attempts;
      recordDiagnostic(
        '[$ts] offline-fgs: parked mangaId=$mangaId chapterId=$chapterId '
        'attempt=$attempts reason="$reason"\n',
      );
    } else {
      recordDiagnostic('[$ts] offline-fgs: parked (no chapter attributed)\n');
    }

    if (_parkedUntil?.isAfter(_now()) ?? false) return;
    final delay = _nextBackoff();
    _armPark(delay);
    logger.i('Offline: server unreachable — downloads parked for $delay');
    // Lets the reconnect listener resume us as soon as anything else in the app
    // reaches the server, instead of waiting out the backoff.
    _ref.read(serverUnreachableProvider.notifier).set(true);
    _ref.read(offlineDownloadRestrictionProvider.notifier).set('connection');
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
    _parkedUntil = _now().add(delay);
    _parkTimer?.cancel();
    _parkTimer = _timer(delay, () => unawaited(_onParkExpired()));
  }

  Future<void> _onParkExpired() async {
    _parkedUntil = null;
    await ensureServiceRunning();
    // The start can decline — Android refusing the service, Wi-Fi-only holding
    // it back — and the deadline is gone by then, so without re-arming here the
    // queue would sit with nothing left to wake it.
    if (_parkedUntil != null || _blocked || _isPaused() || _suppressRestarts) {
      return;
    }
    if (await _gateway.isRunningService) return;
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
    if (until.difference(_now()) > _minParkBackoff) {
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
      if (!await _gateway.isRunningService) break;
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
  Future<void> _notifyPaused(_PauseReason reason) =>
      _publishStall(reason == _PauseReason.wifi ? 'wifi' : 'connection');

  Future<void> _runMutation(Future<void> Function() action) {
    final operation = _mutationTail.then((_) => action());
    _mutationTail = operation.then(
      (_) {},
      onError: (Object error, StackTrace stack) {
        logger.e(
          'Offline: applying worker result failed',
          error: error,
          stackTrace: stack,
        );
      },
    );
    return operation;
  }

  Future<void> _onChapterDone(Map data) async {
    await _runMutation(() => _applyChapterDone(data));
    // Drain handshake: if the worker just self-stopped, do post-stop
    // reconciliation + a drift requery in case work was enqueued during the
    // async stop window (CRITICAL-1).
    if (!await _gateway.isRunningService) {
      await _onServiceStopped();
    }
  }

  Future<void> _applyChapterDone(Map data) async {
    final chapterId = data['chapterId'] as int?;
    final status = data['status'] as String?;
    // Ahead of the awaits below: this event races the worker's `parked` message,
    // and the stop handshake at the end of this method would otherwise restart
    // the service before the latch is set.
    if (status == 'offline') {
      _onParked(
        chapterId: chapterId,
        mangaId: data['mangaId'] as int?,
        reason: data['reason'] as String?,
      );
    }
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
        if (ch == null ||
            ch.deviceState == OfflineDeviceState.none ||
            (data['gen'] as int? ?? 0) != ch.downloadGeneration) {
          return;
        }
        final result = await commitStagedChapter(
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
          // This chapter succeeded, so any earlier parks blamed on it were a
          // transient blip, not its source being gone — don't let them count
          // toward giving up on it if it ever parks again later.
          _chapterParkAttempts.remove(chapterId);
          _commitFailures.remove(chapterId);
        } else {
          // The worker reports the chapter downloaded, but the commit didn't
          // publish it.
          //
          // `refused`: chapter was deleted or re-queued under a new generation
          // while the download was in flight. Drift already reflects the new
          // state (none / queued for the new gen) — do not touch it.
          //
          // `incomplete`/`noStaging`: staging was missing or empty after the
          // download. The row is still `downloading` in drift, which means
          // `_pendingChapters()` will return it on every `afterDrained` restart
          // → infinite phantom-download loop. Fix: reset to `queued` so it
          // re-downloads from scratch, or mark `error` after _maxCommitFailures
          // consecutive failures so it leaves the queue entirely.
          if (ch.deviceState != OfflineDeviceState.none &&
              result != ChapterCommitResult.refused) {
            final attempts = (_commitFailures[chapterId] ?? 0) + 1;
            _commitFailures[chapterId] = attempts;
            if (attempts >= _maxCommitFailures) {
              _commitFailures.remove(chapterId);
              await _db.setChapterDeviceState(
                chapterId,
                OfflineDeviceState.error,
              );
              _sessionFailed++;
            } else {
              await _db.setChapterDeviceState(
                chapterId,
                OfflineDeviceState.queued,
                bytes: 0,
              );
            }
          }
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
  }

  Future<void> _onServiceStopped() async {
    await _replay(); // final log replay → drift
    await _wipeWorkOrderAuth();
    // Anything queued during the async stop? Restart to pick it up.
    await ensureServiceRunning();
  }

  // ---------------------------------------------------------------------------
  // Work order + auth snapshot / write-back
  // ---------------------------------------------------------------------------

  Future<String?> _writeWorkOrder() async {
    final ownership = BackgroundDownloadLock(
      File('${_paths.baseDir}/.bg_lock'),
    );
    if (!await ownership.acquire('publish-service')) {
      await ownership.requestYield();
      if (_controlCount == 0 && !_blocked && !_isPaused()) {
        _armPark(_minParkBackoff);
      }
      return null;
    }
    try {
      await _wipeWorkOrderAuth();
      return await withWorkOrderAdmission(_paths.baseDir, () async {
        final pending = await _pendingChapters();
        if (_isPaused() || _suppressRestarts || pending.isEmpty) return null;
        final attemptId = "${_now().microsecondsSinceEpoch}-$_recoveryEpoch";
        final auth = _snapshotAuth();
        final order = BackgroundWorkOrder(
          attemptId: attemptId,
          chapterIds: [for (final c in pending) c.id],
          mangaIdByChapter: {for (final c in pending) c.id: c.mangaId},
          generationByChapter: {for (final c in pending) c.id: _genOf(c)},
          identityEpoch: CatchupStateStore(
            _ref.read(sharedPreferencesProvider),
          ).identityEpoch,
          catalogServerId: _ref
              .read(sharedPreferencesProvider)
              .getString(DBKeys.offlineCatalogServerId.name),
          serverBase: _ref.read(serverUrlProvider) ?? '',
          port: _ref.read(serverPortProvider),
          addPort: _ref.read(serverPortToggleProvider).ifNull(),
          wifiOnly: _ref.read(offlineWifiOnlyProvider) ?? true,
          auth: auth,
          baseDir: _paths.baseDir,
        );
        await _gateway.remove(kAcceptedWorkOrderKey);
        try {
          await _gateway.write(kTokenRecordKey, jsonEncode(auth.toJson()));
          await _gateway.write(kWorkOrderKey, jsonEncode(order.toJson()));
        } catch (_) {
          await _gateway.remove(kTokenRecordKey);
          await _gateway.remove(kWorkOrderKey);
          rethrow;
        }
        return attemptId;
      });
    } finally {
      await ownership.release();
    }
  }

  Future<void> _invalidateAttempt(String attemptId) =>
      withWorkOrderAdmission(_paths.baseDir, () async {
        final current = decodeWorkOrder(await _gateway.read(kWorkOrderKey));
        if (current?.attemptId != attemptId) return;
        if (await _gateway.read(kAcceptedWorkOrderKey) == attemptId) return;
        await _gateway.remove(kWorkOrderKey);
        await _gateway.remove(kTokenRecordKey);
      });

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
      extraHeaders: Map<String, String>.from(
        _ref.read(customHttpHeadersProvider).value ?? const {},
      ),
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
  Future<void> _wipeWorkOrderAuth() => withWorkOrderAdmission(
    _paths.baseDir,
    () async {
      if (await _gateway.isRunningService) return;
      final order = decodeWorkOrder(await _gateway.read(kWorkOrderKey));
      final accepted = await _gateway.read(kAcceptedWorkOrderKey);
      if (order != null && order.attemptId != accepted) return;
      final raw = await _gateway.read(kTokenRecordKey);
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
      await _gateway.remove(kTokenRecordKey);
      await _gateway.remove(kWorkOrderKey);
    },
  );

  // ---------------------------------------------------------------------------
  // Wi-Fi-only main-side enforcement
  // ---------------------------------------------------------------------------

  /// True when the active connection is metered (no Wi-Fi/ethernet).
  /// `connectivity_plus` returns a list; empty/none is treated as metered-ish
  /// so a wifi-only batch doesn't start.
  Future<bool> _isMetered() async {
    final result = await _connectivity();
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
    if (!_isAndroid()) return;
    final wifiOnly = _ref.read(offlineWifiOnlyProvider) ?? true;
    final hasUnmetered =
        result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
    final hasConnection =
        result.any((r) => r != ConnectivityResult.none) && result.isNotEmpty;
    unawaited(() async {
      if (_isPaused()) {
        await _clearStall();
        return;
      }
      if ((await _pendingChapters()).isEmpty) {
        await _clearStall();
        return;
      }
      await _refreshRestriction();
      if (hasConnection && wifiOnly && !hasUnmetered) {
        // Wi-Fi-only and dropped to metered: stop the running service (chapters
        // stay `downloading` and resume on Wi-Fi).
        if (await _gateway.isRunningService) {
          logger.i(
            'Offline: dropped to metered with Wi-Fi-only — stopping FGS',
          );
          await _gateway.stop();
          await _notifyPaused(_PauseReason.wifi);
        }
        return;
      }
      // Only the Wi-Fi-only case used to stop the service, so with that off
      // the worker kept running against a network that was gone.
      if (!hasConnection) {
        if (await _gateway.isRunningService) {
          logger.i('Offline: no connection — stopping FGS');
          // Before the stop: the cancelled chapter's terminal event runs the
          // restart handshake, which would put a fresh worker straight back on
          // a network that isn't there.
          _armPark(_nextBackoff());
          await _gateway.stop();
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
  // ---------------------------------------------------------------------------
  // TokenBroker adapter (main side)
  // ---------------------------------------------------------------------------

  /// A [TokenBroker] backed by FFT storage, sharing the worker's gen-versioned
  /// record — for callers/tests coordinating a refresh from the main isolate.
  /// Only ui_login refreshes; network refresh is delegated to [refreshFn].
  TokenBroker mainSideBroker({
    required Future<RefreshAttempt> Function(String refreshToken) refreshFn,
  }) => TokenBroker(
    read: () async {
      final raw = await _gateway.read(kTokenRecordKey);
      if (raw != null) {
        return BackgroundTokenRecord.fromJson(
          jsonDecode(raw) as Map<String, Object?>,
        );
      }
      return _snapshotAuth();
    },
    write: (r) => _gateway.write(kTokenRecordKey, jsonEncode(r.toJson())),
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
