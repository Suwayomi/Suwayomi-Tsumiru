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
import 'package:path_provider/path_provider.dart';

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
import '../../../notifications/data/notification_state_store.dart';
import '../../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../account_storage_paths.dart';
import '../chapter_commit.dart';
import '../offline_database.dart';
import '../offline_download_progress.dart';
import '../offline_download_stall.dart';
import '../offline_page_store.dart';
import '../offline_paths.dart';
import '../offline_repository.dart';
import '../offline_server_identity_repository.dart';
import '../offline_settings_providers.dart';
import '../offline_storage_identity.dart';
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

/// Android worker owner on the main isolate; the main-isolate pump must not also download.
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
  String? _activeAttemptId;
  Future<void>? _startupFuture;

  @visibleForTesting
  Future<void> get startupSettled => _startupFuture ?? Future.value();
  Future<void> _identityTail = Future.value();
  Future<void> _mutationTail = Future.value();
  DateTime? _lastRecovery;
  AppLifecycleState? _lastLifecycle;
  // A shade peek is inactive/resumed too; only hidden/paused/detached marks a background trip.
  bool _wentBackground = false;
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

  int _genOf(OfflineChapter c) => c.downloadGeneration;

  DataCallback? _workerEventCallback;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  ProviderSubscription<AsyncValue<String>>? _identitySubscription;

  // Awaited startup steps must not overlap between enqueue and resume.
  bool _ensuring = false;
  bool _suppressRestarts = false;
  int _controlCount = 0;
  final Object _controlZone = Object();

  // Pending drift rows survive a park; backoff prevents the stop handshake restarting immediately.
  DateTime? _parkedUntil;
  Duration _parkBackoff = _minParkBackoff;
  Timer? _parkTimer;

  // Epoch prevents a slow earlier commit from clearing a later park.
  int _parkEpoch = 0;
  static const _minParkBackoff = Duration(seconds: 15);
  static const _maxParkBackoff = Duration(minutes: 5);

  OfflineDatabase get _db => _ref.read(offlineDatabaseProvider);
  OfflinePaths get _paths => _ref.read(offlinePathsProvider);
  OfflinePageStore get _store => _ref.read(offlinePageStoreProvider);

  BackgroundCompletionLog get _log =>
      BackgroundCompletionLog(File('${_paths.baseDir}/.bg_completion.log'));


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
    final identityFuture = _recoverIdentityTransition();
    unawaited(identityFuture);
    final restoreFuture = _restoreActiveAttempt();
    unawaited(restoreFuture);
    _startupFuture = Future.wait<void>([
      identityFuture.then<void>((_) {}, onError: (_) {}),
      restoreFuture.then<void>((_) {}, onError: (_) {}),
    ]);
    WidgetsBinding.instance.addObserver(this);
    _workerEventCallback ??= _onWorkerEvent;
    _gateway.addCallback(_workerEventCallback!);
    _bindStorage();
    // Provider-level listening would cycle through the server-address dependency during switching.
    _identitySubscription ??= _ref.container.listen(serverInstanceIdProvider, (
      _,
      next,
    ) {
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

  void _bindStorage() {
    if (!_isAndroid() || !_ref.read(offlineEnabledProvider)) return;
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
  }

  Future<void> detachStorage() async {
    _queuePublishTimer?.cancel();
    _handoffTimer?.cancel();
    _parkTimer?.cancel();
    await _pendingSub?.cancel();
    _pendingSub = null;
    await _queuePublishFlight;
    await _mutationTail;
    _pendingSignature = null;
    _activeAttemptId = null;
  }

  Future<void> rebindStorage() async {
    if (_disposed) return;
    _bindStorage();
  }

  void dispose() {
    _disposed = true;
    _identitySubscription?.close();
    _activeAttemptId = null;
    _queuePublishTimer?.cancel();
    _handoffTimer?.cancel();
    unawaited(_pendingSub?.cancel());
    _parkTimer?.cancel();
    // Non-Android registration never touched WidgetsBinding; disposal must not require it either.
    if (!_isAndroid()) return;
    WidgetsBinding.instance.removeObserver(this);
    final cb = _workerEventCallback;
    if (cb != null) _gateway.removeCallback(cb);
    unawaited(_connSub?.cancel());
  }


  /// Merges pending work or starts the worker; honors Wi-Fi-only.
  /// [force] bypasses park backoff for user actions or proof the server answered.
  Future<void> ensureServiceRunning({bool force = false}) async {
    if (force && _controlCount > 0) _handoffForce = true;
    if (!_isAndroid() ||
        _disposed ||
        _suppressRestarts ||
        _controlCount > 0 ||
        !_identityAllowed) {
      return;
    }
    await _ref.read(sharedPreferencesProvider).reload();
    if (_disposed ||
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
        await _restoreActiveAttempt();
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
            _activeAttemptId = null;
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

  /// Restarts with a fresh endpoint snapshot after a network handover.
  Future<void> restartForEndpointChange() => ensureServiceRunning(force: true);

  Future<T> changeIdentity<T>(
    Future<T> Function() action, {
    bool preserveSession = false,
  }) async {
    final credentials = _ref.read(authCredentialsStoreProvider.notifier);
    return credentials.withIdentityChange(
      () => _changeIdentityOwned(action),
      preserveSession: preserveSession,
      expectedEpoch: preserveSession ? null : credentials.serverEpoch,
    );
  }

  Future<String> _storageRoot() async {
    if (_ref.read(offlineEnabledProvider)) return _paths.baseDir;
    final root = '${(await getApplicationSupportDirectory()).path}/offline';
    final preferences = _ref.read(sharedPreferencesProvider);
    final catalog = preferences.getString(
      offlineCatalogServerIdKey(preferences),
    );
    if (preferences.getBool(offlineNonAccountScopedKey) == true) {
      return nonAccountStoragePath(root);
    }
    return preferences.getBool(offlineAccountScopedKey) == true &&
            catalog != null
        ? accountStoragePath(root, catalog)
        : root;
  }

  final _storageRootZone = Object();
  String? get ownedStorageRoot => Zone.current[_storageRootZone] as String?;

  Future<T> _changeIdentityOwned<T>(Future<T> Function() action) async {
    if (Zone.current[_controlZone] == this) return action();
    if (!_isAndroid() && !_ref.read(offlineEnabledProvider)) return action();
    final previous = _identityTail;
    final finished = Completer<void>();
    _identityTail = finished.future;
    await previous;
    _suppressRestarts = true;
    _activeAttemptId = null;
    final preferences = _ref.read(sharedPreferencesProvider);
    final state = CatchupStateStore(preferences);
    try {
      await state.setIdentityChanging(true);
      await state.setIdentityAuthorized(false);
      final root = await _storageRoot();
      return await _withOwnership(() async {
        if (_isAndroid()) {
          await withWorkOrderAdmission(root, () async {
            await _gateway.remove(kWorkOrderKey);
            await _gateway.remove(kTokenRecordKey);
          });
        }
        await withBackgroundScheduleLock(() async {
          await state.clearState(preserveLedger: true);
          await NotificationStateStore(preferences).clearSession();
        }, baseDir: root);
        if (_isAndroid() && _ref.read(offlineEnabledProvider)) {
          await _clearStall();
        }
        final result = await action();
        await state.setIdentityChanging(false);
        _ref.invalidate(serverInstanceIdProvider);
        return result;
      }, identityChange: true);
    } finally {
      try {
        await state.setIdentityChanging(false);
        if (_isAndroid()) await reconcileBackgroundSchedule();
      } finally {
        _suppressRestarts = false;
        finished.complete();
      }
    }
  }

  Future<List<OfflineChapter>> _pendingChapters() async {
    final queued = await _db.chaptersInState(OfflineDeviceState.queued);
    final downloading = await _db.chaptersInState(
      OfflineDeviceState.downloading,
    );
    return [...queued, ...downloading];
  }


  /// Call after writing queued state to drift; the queue is read from drift, not [chapterIds].
  Future<void> onEnqueued(List<int> chapterIds) =>
      requestStart(userInitiated: true);

  /// User actions bypass backoff; automatic triggers may only shorten it to the minimum delay.
  Future<void> requestStart({bool userInitiated = false}) {
    if (userInitiated) {
      _allowRecovery();
      if (_controlCount > 0) _handoffForce = true;
    }
    if (!userInitiated) _retrySooner();
    return ensureServiceRunning(force: userInitiated);
  }

  // Read persisted pause synchronously so unhydrated providers cannot bypass the start gate.
  bool _isPaused() {
    final prefs = _ref.read(sharedPreferencesProvider);
    final state = CatchupStateStore(prefs);
    final catalogId = state.catalogServerId;
    return state.paused ||
        (catalogId != null && state.downloadPermissionPaused(catalogId));
  }

  /// Caller must persist pause first; the worker cancels resumably and self-stops.
  Future<void> pause() async {
    if (!_isAndroid()) return;
    _activeAttemptId = null;
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
      // Let the worker self-stop; main-side stopService could interrupt a page write.
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

  Future<T> withOwnership<T>(Future<T> Function() action) =>
      _withOwnership(action);

  Future<T> _withOwnership<T>(
    Future<T> Function() action, {
    bool identityChange = false,
  }) async {
    if (Zone.current[_controlZone] == this) return action();
    if (!_isAndroid() && !_ref.read(offlineEnabledProvider)) return action();
    final current = _ref
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    void checkSession() {
      if (!identityChange && !current()) {
        throw StateError('Authentication session changed');
      }
    }

    checkSession();
    final root = await _storageRoot();
    final lock = BackgroundDownloadLock(File('$root/.bg_lock'));
    _controlCount++;
    try {
      var acquired = await lock.acquire('control');
      if (!acquired) {
        await lock.requestYield();
        if (_isAndroid() && await _gateway.isRunningService) _pauseWorker();
      }
      for (var i = 0; !acquired && i < 300; i++) {
        checkSession();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        acquired = await lock.acquire('control');
        if (!acquired) await lock.requestYield();
      }
      if (!acquired) {
        throw StateError('Downloads did not stop; action remains pending');
      }
      await _mutationTail;
      checkSession();
      return await runZoned(() async {
        final result = await action();
        await _publishQueue();
        return result;
      }, zoneValues: {_controlZone: this, _storageRootZone: root});
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

  /// Caller must clear persisted pause first.
  Future<void> resume() => requestStart(userInitiated: true);

  Future<void> stopAndClearWorkOrder() async {
    if (!_isAndroid()) return;
    _suppressRestarts = true;
    _activeAttemptId = null;
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

  /// Cancels worker activity only; the caller deletes drift rows and files.
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

  /// Call after bumping drift generation to reject stale completions.
  Future<void> recordChapterDeleted(int chapterId, int newGeneration) async {
    if (!_isAndroid()) return;
    await _log.appendDeleted(chapterId, newGeneration);
  }

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


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isAndroid()) return;
    final previous = _lastLifecycle;
    _lastLifecycle = state;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _wentBackground = true;
      return;
    }
    if (state == AppLifecycleState.resumed) {
      // Only actual background returns replay work; shade peeks must not interrupt active downloads.
      final wasBackground = _wentBackground || previous == null;
      _wentBackground = false;
      if (!wasBackground) return;
      unawaited(replayOnResume());
    }
  }

  Future<void> replayOnResume() async {
    _allowRecovery();
    _retrySooner();
    await _replay();
    await ensureServiceRunning();
  }

  Future<void> replayAtLaunchAndMaybeStart() async {
    if (!_isAndroid()) return;
    await _replay();
    await maybeStartAfterReplay();
  }

  /// Replay before launch reconciliation, then start the service afterward.
  Future<void> replayAtLaunch() async {
    if (!_isAndroid()) return;
    await _restoreActiveAttempt();
    await _replay();
  }

  Future<void> maybeStartAfterReplay() async {
    if (!_isAndroid()) return;
    _allowRecovery();
    _retrySooner();
    await ensureServiceRunning();
  }

  Future<void> _replay({bool Function()? isCurrent}) => withOwnership(() async {
    if (isCurrent?.call() == false) return;
    await replayCompletionLog(
      db: _db,
      store: _store,
      log: _log,
      onTimeout: () => _recordTimeout(blockRetry: false),
      catalogServerId: _ref
          .read(sharedPreferencesProvider)
          .getString(
            offlineCatalogServerIdKey(_ref.read(sharedPreferencesProvider)),
          ),
    );
  });


  bool _eventCurrent(Map data) {
    final controls = CatchupStateStore(_ref.read(sharedPreferencesProvider));
    return !_disposed &&
        !_suppressRestarts &&
        _activeAttemptId != null &&
        data['attemptId'] == _activeAttemptId &&
        _identityAllowed &&
        controls.identityAuthorized &&
        !controls.identityChanging &&
        data['catalogServerId'] is String &&
        data['catalogServerId'] == controls.catalogServerId &&
        data['identityEpoch'] is int &&
        data['identityEpoch'] == controls.identityEpoch;
  }

  void _onWorkerEvent(Object data) {
    if (data is! Map) return;
    // Drop queued port events while clearing the catalog so they cannot recreate rows.
    if (_controlCount > 0 || !_eventCurrent(data)) return;
    switch (data['kind']) {
      case 'timedOut':
        final occurred = DateTime.tryParse(data['at'] as String? ?? '');
        unawaited(
          _runMutation(() async {
            if (!_eventCurrent(data)) return;
            await _recordTimeout(
              isCurrent: () => _eventCurrent(data),
              blockRetry:
                  occurred == null ||
                  _lastRecovery == null ||
                  occurred.isAfter(_lastRecovery!),
            );
          }),
        );
      case 'chapterStart':
        unawaited(
          _runMutation(() async {
            if (!_eventCurrent(data)) return;
            await _applyChapterStart(
              data['chapterId'] as int,
              data['total'] as int?,
              data['gen'] as int? ?? 0,
              () => _eventCurrent(data),
            );
          }),
        );
      case 'page':
        unawaited(_applyPageEvent(data));
      case 'chapterDone':
        unawaited(_onChapterDone(data));
      case 'drained':
        unawaited(_onDrained(data));
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

  Future<void> _recordTimeout({
    required bool blockRetry,
    bool Function()? isCurrent,
  }) async {
    if (_isPaused() ||
        _suppressRestarts ||
        (await _pendingChapters()).isEmpty) {
      return;
    }
    if (isCurrent?.call() == false) return;
    if (blockRetry) _retryBlocked = true;
    await _ref.read(offlineDownloadsStalledProvider.notifier).set('budget');
    await _refreshRestriction();
  }

  // Diagnostic only: repeated network parks do not prove a chapter is unservable.
  final Map<int, int> _chapterParkAttempts = {};

  // Cap failed commits so incomplete staging cannot restart indefinitely as a pending download.
  static const _maxCommitFailures = 3;
  final Map<int, int> _commitFailures = {};

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
    _ref
        .read(serverUnreachableProvider.notifier)
        .set(true, reason: 'background-downloads-parked');
    _ref.read(offlineDownloadRestrictionProvider.notifier).set('connection');
    // Stopping the service removes its notification; surface the first parked state separately.
    if (delay == _minParkBackoff) unawaited(_notifyPaused(_PauseReason.server));
  }

  Duration _nextBackoff() {
    final delay = _parkBackoff;
    _parkBackoff = delay * 2 > _maxParkBackoff ? _maxParkBackoff : delay * 2;
    return delay;
  }

  void _armPark(Duration delay) {
    // Invalidate older commits before they can clear this newly armed park.
    _parkEpoch++;
    _parkedUntil = _now().add(delay);
    _parkTimer?.cancel();
    _parkTimer = _timer(delay, () => unawaited(_onParkExpired()));
  }

  Future<void> _onParkExpired() async {
    _parkedUntil = null;
    await ensureServiceRunning();
    // A declined service start consumes the timer; re-arm so pending work still has a wakeup.
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

  // Keep at least the minimum delay so link flapping cannot repeatedly restart the service.
  void _retrySooner() {
    final until = _parkedUntil;
    if (until == null) return;
    if (until.difference(_now()) > _minParkBackoff) {
      _armPark(_minParkBackoff);
    }
  }

  // Check deletion transactionally: remove messages can arrive after already-queued worker events.
  Future<void> _applyChapterStart(
    int id,
    int? total,
    int eventGen,
    bool Function() isCurrent,
  ) async {
    await _db.transaction(() async {
      final c = await _db.chapterById(id);
      if (!isCurrent()) return;
      if (c == null ||
          (c.deviceState != OfflineDeviceState.queued &&
              c.deviceState != OfflineDeviceState.downloading) ||
          eventGen != c.downloadGeneration) {
        return;
      }
      await _db.setChapterDeviceState(id, OfflineDeviceState.downloading);
      if (total != null && total > 0) {
        await _db.setChapterPageCount(id, total);
      }
    });
  }

  // Staging is unpublished; page events update progress only.
  Future<void> _applyPageEvent(Map data) async {
    final total = data['total'] as int? ?? 0;
    if (total <= 0) return;
    final id = data['chapterId'] as int;
    // Events queued before deletion must not re-enter the progress map.
    final c = await _db.chapterById(id);
    if (!_eventCurrent(data)) return;
    if (c == null || c.deviceState == OfflineDeviceState.none) return;
    if ((data['gen'] as int? ?? 0) < c.downloadGeneration) return;
    _ref
        .read(offlineDownloadProgressProvider.notifier)
        .start(id, total: total, done: data['done'] as int? ?? 0);
  }

  // Wait for self-stop before rechecking work queued during the shutdown window.
  Future<void> _onDrained(Map data) async {
    for (var i = 0; i < 20; i++) {
      if (!await _gateway.isRunningService) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    final pending = await _pendingChapters();
    if (!_eventCurrent(data)) return;
    if (pending.isNotEmpty) {
      await ensureServiceRunning();
      return;
    }
    await _notifyDownloadsComplete(() => _eventCurrent(data));
  }

  int _sessionDownloaded = 0;
  int _sessionFailed = 0;
  String? _sessionFailureMessage;

  Future<void> _notifyDownloadsComplete(bool Function() isCurrent) async {
    final done = _sessionDownloaded;
    final failed = _sessionFailed;
    final message = _sessionFailureMessage;
    _sessionFailureMessage = null;
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
      if (!isCurrent()) return;
      if (done > 0) {
        await service.showDownloadsComplete(
          title: l10n.notificationDownloadsCompleteTitle,
          body: l10n.notificationDownloadsCompleteBody(done),
        );
      }
      if (failed > 0 && isCurrent()) {
        final body = l10n.notificationDownloadErrorBody(failed);
        await service.showDownloadError(
          l10n.notificationDownloadErrorTitle,
          message == null || message.isEmpty ? body : '$body\n$message',
        );
      }
    } catch (_) {
    }
  }

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
    await _runMutation(() async {
      if (!_eventCurrent(data)) return;
      await _applyChapterDone(data);
    });
    // Recheck drift after self-stop to catch work enqueued during shutdown.
    if (!await _gateway.isRunningService && _eventCurrent(data)) {
      await _onServiceStopped(isCurrent: () => _eventCurrent(data));
    }
  }

  Future<void> _applyChapterDone(Map data) async {
    final chapterId = data['chapterId'] as int?;
    final status = data['status'] as String?;
    // Latch offline before awaiting, or the terminal handshake can restart before parked arrives.
    if (status == 'offline') {
      _onParked(
        chapterId: chapterId,
        mangaId: data['mangaId'] as int?,
        reason: data['reason'] as String?,
      );
    } else if (status == 'authFailed') {
      _armPark(_nextBackoff());
    }
    final epoch = _parkEpoch;
    // Cancel events have null status too; clear their progress to avoid stale percentages on retry.
    if (chapterId != null) {
      _ref.read(offlineDownloadProgressProvider.notifier).clear(chapterId);
    }
    if (chapterId != null && status != null) {
      // Only the main isolate publishes staged chapters and writes their catalog rows.
      if (status == 'downloaded') {
        final ch = await _db.chapterById(chapterId);
        if (!_eventCurrent(data)) return;
        if (ch == null ||
            ch.deviceState == OfflineDeviceState.none ||
            (data['gen'] as int? ?? 0) != ch.downloadGeneration) {
          recordDiagnostic(
            '[${_now().toIso8601String()}] offline-fgs: chapter-dropped '
            'chapterId=$chapterId reason=stale-or-deleted '
            'deviceState=${ch?.deviceState.name ?? 'missing'}\n',
          );
          return;
        }
        final result = await commitStagedChapter(
          db: _db,
          store: _store,
          mangaId: ch.mangaId,
          chapterId: chapterId,
        );
        // Count only published chapters, not stale, deleted, or incomplete completions.
        if (!_eventCurrent(data)) return;
        if (result == ChapterCommitResult.committed) {
          _sessionDownloaded++;
          recordDiagnostic(
            '[${_now().toIso8601String()}] offline-fgs: downloaded-chapter '
            'mangaId=${ch.mangaId} chapterId=$chapterId\n',
          );
          // Do not clear a park raised by a later chapter while this commit was running.
          if (_parkEpoch == epoch) _clearPark();
          _chapterParkAttempts.remove(chapterId);
          _commitFailures.remove(chapterId);
        } else {
          // Refused commits preserve newer drift state; missing/incomplete staging must retry under a cap.
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
              recordDiagnostic(
                '[${_now().toIso8601String()}] offline-fgs: commit-failed '
                'mangaId=${ch.mangaId} chapterId=$chapterId '
                'result=${result.name} attempts=$attempts/$_maxCommitFailures '
                '— marked error\n',
              );
            } else {
              await _db.setChapterDeviceState(
                chapterId,
                OfflineDeviceState.queued,
                bytes: 0,
              );
              recordDiagnostic(
                '[${_now().toIso8601String()}] offline-fgs: commit-incomplete '
                'mangaId=${ch.mangaId} chapterId=$chapterId '
                'result=${result.name} attempts=$attempts/$_maxCommitFailures '
                '— requeued\n',
              );
            }
          } else if (result == ChapterCommitResult.refused) {
            recordDiagnostic(
              '[${_now().toIso8601String()}] offline-fgs: commit-refused '
              'mangaId=${ch.mangaId} chapterId=$chapterId '
              '— deleted or re-queued under a new generation\n',
            );
          }
        }
      } else {
        await applyBackgroundTerminalState(
          db: _db,
          chapterId: chapterId,
          status: status,
          eventGeneration: data['gen'] as int? ?? 0,
        );
        if (status == 'error') {
          _sessionFailed++;
          final message = data['reason'] as String?;
          if (message != null && message.isNotEmpty) {
            _sessionFailureMessage = message;
          }
        }
        recordDiagnostic(
          '[${_now().toIso8601String()}] offline-fgs: chapter-terminal '
          'mangaId=${data['mangaId']} chapterId=$chapterId status=$status '
          'reason=${data['reason']}\n',
        );
      }
    }
  }

  Future<void> _onServiceStopped({bool Function()? isCurrent}) async {
    if (isCurrent?.call() == false) return;
    await _replay(isCurrent: isCurrent); // final log replay → drift
    if (isCurrent?.call() == false) return;
    final sessionCurrent = _ref
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    await _wipeWorkOrderAuth(isCurrent: isCurrent);
    if (!sessionCurrent() || !_identityAllowed || _suppressRestarts) return;
    await ensureServiceRunning();
  }


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
              .getString(
                offlineCatalogServerIdKey(_ref.read(sharedPreferencesProvider)),
              ),
          serverBase: _ref.read(serverUrlProvider) ?? '',
          lanUrl: _ref.read(serverLanUrlProvider),
          externalUrl:
              _ref.read(serverExternalUrlProvider) ?? DBKeys.serverUrl.initial,
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
        _activeAttemptId = attemptId;
        recordDiagnostic(
          '[${_now().toIso8601String()}] offline-fgs: work-order-dispatched '
          'count=${pending.length} '
          'chapterIds=[${[for (final c in pending) c.id].join(',')}]\n',
        );
        return attemptId;
      });
    } finally {
      await ownership.release();
    }
  }

  Future<void> _restoreActiveAttempt() async {
    if (_disposed || !_ref.read(offlineEnabledProvider)) return;
    await withWorkOrderAdmission(_paths.baseDir, () async {
      final order = decodeWorkOrder(await _gateway.read(kWorkOrderKey));
      if (_disposed) return;
      final controls = CatchupStateStore(_ref.read(sharedPreferencesProvider));
      if (_disposed ||
          _suppressRestarts ||
          !_identityAllowed ||
          controls.identityChanging ||
          !controls.identityAuthorized) {
        return;
      }
      _activeAttemptId =
          order?.catalogServerId == controls.catalogServerId &&
              order?.identityEpoch == controls.identityEpoch
          ? order?.attemptId
          : null;
    });
  }

  Future<void> _invalidateAttempt(String attemptId) =>
      withWorkOrderAdmission(_paths.baseDir, () async {
        final current = decodeWorkOrder(await _gateway.read(kWorkOrderKey));
        if (current?.attemptId != attemptId) return;
        if (await _gateway.read(kAcceptedWorkOrderKey) == attemptId) return;
        _activeAttemptId = null;
        await _gateway.remove(kWorkOrderKey);
        await _gateway.remove(kTokenRecordKey);
      });

  BackgroundTokenRecord _snapshotAuth() {
    final authType = _ref.read(authTypeKeyProvider) ?? AuthType.none;
    final basicToken = _ref.read(credentialsProvider).value;
    final creds = _ref.read(authCredentialsStoreProvider).value;
    return BackgroundTokenRecord(
      gen: 0,
      authType: authType.name,
      endpoint: _effectiveEndpoint(),
      identityEpoch: CatchupStateStore(
        _ref.read(sharedPreferencesProvider),
      ).identityEpoch,
      catalogServerId: CatchupStateStore(
        _ref.read(sharedPreferencesProvider),
      ).catalogServerId,
      originalRefreshToken: creds?.uiRefreshToken,
      accessToken: creds?.uiAccessToken,
      refreshToken: creds?.uiRefreshToken,
      basicCredential: basicToken,
      simpleCookie: creds?.simpleLoginCookie,
      extraHeaders: Map<String, String>.from(
        _ref.read(customHttpHeadersProvider).value ?? const {},
      ),
    );
  }

  String _effectiveEndpoint() {
    final usePort = _ref.read(serverPortToggleProvider).ifNull();
    final port = usePort ? _ref.read(serverPortProvider) : null;
    return '${_ref.read(serverUrlProvider)}|${port ?? '-'}';
  }

  // Copy rotated tokens back before clearing the worker auth snapshot.
  Future<void> _wipeWorkOrderAuth({bool Function()? isCurrent}) =>
      withWorkOrderAdmission(_paths.baseDir, () async {
        if (await _gateway.isRunningService) return;
        final order = decodeWorkOrder(await _gateway.read(kWorkOrderKey));
        final accepted = await _gateway.read(kAcceptedWorkOrderKey);
        if (order != null && order.attemptId != accepted) return;
        final raw = await _gateway.read(kTokenRecordKey);
        if (isCurrent?.call() == false) return;
        if (raw != null) {
          try {
            final record = BackgroundTokenRecord.fromJson(
              jsonDecode(raw) as Map<String, Object?>,
            );
            final controls = CatchupStateStore(
              _ref.read(sharedPreferencesProvider),
            );
            final store = _ref.read(authCredentialsStoreProvider.notifier);
            if (record.gen > 0 &&
                record.authType == 'uiLogin' &&
                record.accessToken != null &&
                record.refreshToken != null &&
                record.originalRefreshToken != null &&
                record.identityEpoch == controls.identityEpoch &&
                record.catalogServerId != null &&
                record.catalogServerId == controls.catalogServerId &&
                controls.identityAuthorized &&
                record.endpoint == _effectiveEndpoint()) {
              await store.refreshUiLoginTokens(
                accessToken: record.accessToken!,
                refreshToken: record.refreshToken!,
                originalRefreshToken: record.originalRefreshToken!,
                forEpoch: store.serverEpoch,
              );
            }
          } catch (e) {
            logger.e('Offline: failed to read back worker token record: $e');
          }
        }
        if (isCurrent?.call() == false) return;
        _activeAttemptId = null;
        await _gateway.remove(kTokenRecordKey);
        await _gateway.remove(kWorkOrderKey);
      });


  // Treat empty/none connectivity as metered so Wi-Fi-only never starts offline.
  Future<bool> _isMetered() async {
    final result = await _connectivity();
    final hasUnmetered =
        result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
    return !hasUnmetered;
  }

  // Background-only connectivity changes are reconciled on foreground/launch.
  void _onConnectivityChanged(List<ConnectivityResult> result) {
    if (!_isAndroid() || _disposed || !_ref.read(offlineEnabledProvider)) {
      return;
    }
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
        if (await _gateway.isRunningService) {
          logger.i(
            'Offline: dropped to metered with Wi-Fi-only — stopping FGS',
          );
          await _gateway.stop();
          await _notifyPaused(_PauseReason.wifi);
        }
        return;
      }
      if (!hasConnection) {
        if (await _gateway.isRunningService) {
          logger.i('Offline: no connection — stopping FGS');
          // Park before stopping so the cancelled terminal event cannot restart on the dead link.
          _armPark(_nextBackoff());
          await _gateway.stop();
          await _notifyPaused(_PauseReason.server);
        }
        return;
      }
      final pending = await _pendingChapters();
      if (pending.isEmpty) return;
      _retrySooner();
      await ensureServiceRunning();
    }());
  }



  TokenBroker mainSideBroker({
    required Future<RefreshAttempt> Function(String refreshToken) refreshFn,
  }) {
    final original = _snapshotAuth();
    return TokenBroker(
      expectedIdentity: original,
      read: () async {
        final raw = await _gateway.read(kTokenRecordKey);
        if (raw != null) {
          return BackgroundTokenRecord.fromJson(
            jsonDecode(raw) as Map<String, Object?>,
          );
        }
        return _snapshotAuth();
      },
      write: (r) => withWorkOrderAdmission(_paths.baseDir, () async {
        if (_ref.read(authCredentialsStoreProvider.notifier).identityChanging ||
            !_snapshotAuth().sameIdentity(original)) {
          return;
        }
        final raw = await _gateway.read(kTokenRecordKey);
        if (_ref.read(authCredentialsStoreProvider.notifier).identityChanging ||
            !_snapshotAuth().sameIdentity(original) ||
            raw == null ||
            !BackgroundTokenRecord.fromJson(
              jsonDecode(raw) as Map<String, Object?>,
            ).sameIdentity(original)) {
          return;
        }
        await _gateway.write(kTokenRecordKey, jsonEncode(r.toJson()));
      }),
      refreshFn: refreshFn,
    );
  }
}

final backgroundDownloadControllerProvider =
    Provider<BackgroundDownloadController>((Ref ref) {
      final controller = BackgroundDownloadController(ref);
      // Container teardown must cancel retry timers and listeners before Ref disposal.
      ref.onDispose(controller.dispose);
      return controller;
    });

/// Call once early in main; no-op outside Android.
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

enum _PauseReason { wifi, server }
