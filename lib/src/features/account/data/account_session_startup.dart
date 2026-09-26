// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart'
    show ProviderListenable;

import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/platform/is_android_native.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../migration/controller/bulk_migration_providers.dart';
import '../../notifications/controller/notifications_controller.dart';
import '../../offline/data/account_storage_recovery_state.dart';
import '../../offline/data/background/background_download_controller_shim.dart';
import '../../offline/data/background/catchup_spec_writer.dart';
import '../../offline/data/background/catchup_work_spec.dart';
import '../../offline/data/chapter_commit.dart';
import '../../offline/data/offline_background_downloads.dart';
import '../../offline/data/offline_chapter_catchup.dart';
import '../../offline/data/offline_download_permission.dart';
import '../../offline/data/offline_download_providers.dart';
import '../../offline/data/offline_repository.dart';
import '../../offline/data/offline_runtime_storage.dart';
import '../../offline/data/offline_server_identity_repository.dart';
import '../../offline/data/server_reachability.dart';
import '../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../domain/account_access.dart';
import 'account_bootstrap.dart';
import 'account_providers.dart';
import 'account_session_storage.dart';

class AccountSessionStartup {
  AccountSessionStartup(this.container)
    : _sessionCurrent = container
          .read(authCredentialsStoreProvider.notifier)
          .captureSession();

  final ProviderContainer container;
  final bool Function() _sessionCurrent;
  final _subscriptions = <ProviderSubscription<dynamic>>[];
  AppLifecycleListener? _lifecycle;
  BackgroundDownloadController? _background;
  Future<void>? _flight;
  bool _started = false;
  bool _disposed = false;
  bool _initialized = false;
  bool _rerun = false;
  bool _restoreUnboundRequested = false;
  bool _endpointChanged = false;
  bool _catchupStarted = false;
  bool _offlineActivationPending = false;
  bool? _downloadsAllowed;
  int _permissionRevision = 0;

  bool get _current => !_disposed && _sessionCurrent();

  int get _currentPermissionRevision {
    final state = CatchupStateStore(container.read(sharedPreferencesProvider));
    final id = state.catalogServerId;
    return id == null ? 0 : state.downloadPermissionRevision(id);
  }

  Future<void> start() {
    if (_started || !_current) return _flight ?? Future.value();
    _started = true;
    _permissionRevision = _currentPermissionRevision;
    container.read(serverEndpointResolverProvider.notifier);
    if (isAndroidNative) {
      _background = container.read(backgroundDownloadControllerProvider);
      _background!.register();
    }
    _subscriptions.add(
      container.listen<String>(currentServerAddressProvider, (previous, next) {
        if (!_current || previous == null || previous == next) return;
        _endpointChanged = true;
        unawaited(_request());
      }),
    );
    _subscriptions.add(
      container.listen<bool>(serverUnreachableProvider, (previous, next) {
        if (_current && previous == true && !next) unawaited(_request());
      }),
    );
    _subscriptions.add(
      container.listen<bool>(offlineActiveProvider, (previous, next) {
        if (!_current || previous == true || !next) return;
        // At launch this flips on as soon as the server's identity loads,
        // while the pass that awaited that identity is still running and is
        // about to read it. Forcing a rerun then repeated the whole launch
        // reconcile and catch-up. Only rerun if the running pass read it
        // before it flipped.
        if (_flight != null) {
          _offlineActivationPending = true;
        } else {
          unawaited(_request());
        }
      }),
    );
    _subscriptions.add(
      container.listen<AccountAccess>(settledAccountAccessProvider, (_, next) {
        if (!_current || next.capability == AccountCapability.unknown) return;
        final allowed = downloadPermissionAllowed(container.read);
        final revision = _currentPermissionRevision;
        final restored =
            allowed &&
            (_downloadsAllowed == false || revision != _permissionRevision);
        _downloadsAllowed = allowed;
        _permissionRevision = revision;
        if (restored) unawaited(_request());
      }),
    );
    _lifecycle = AppLifecycleListener(onPause: _snapshot, onHide: _snapshot);
    return _request(restoreUnbound: false);
  }

  Future<void> _request({bool restoreUnbound = true}) {
    if (!_current) return Future.value();
    _restoreUnboundRequested |= restoreUnbound;
    if (_flight != null) {
      _rerun = true;
      return _flight!;
    }
    final work = Future<void>(() async {
      do {
        _rerun = false;
        _offlineActivationPending = false;
        final restoreUnbound = _restoreUnboundRequested;
        _restoreUnboundRequested = false;
        if (!_current) return;
        try {
          if (container.read(accountStorageRecoveryProvider)?.phase ==
              AccountStorageRecoveryPhase.pending) {
            unawaited(container.read(accountSessionStorageProvider).recover());
          }
          final credentials = container
              .read(authCredentialsStoreProvider)
              .value;
          if (container.read(authTypeKeyProvider) == AuthType.uiLogin &&
              container
                      .read(authCredentialsStoreProvider.notifier)
                      .uiLoginTokens() ==
                  null) {
            return;
          }
          if (restoreUnbound &&
              !container.read(serverUnreachableProvider) &&
              container.read(authTypeKeyProvider) == AuthType.uiLogin &&
              credentials?.accountBinding == null &&
              container
                      .read(authCredentialsStoreProvider.notifier)
                      .uiLoginTokens() !=
                  null) {
            await restoreAccountSession(container);
            if (!_current) return;
          }
          container.invalidate(verifiedServerInstanceIdProvider);
          final catalogId = await container.read(
            verifiedServerInstanceIdProvider.future,
          );
          if (!_current) return;
          try {
            await container.read(refreshAccountAccessProvider)();
          } catch (_) {}
          if (!_current) return;
          if (_initialized && _endpointChanged && isAndroidNative) {
            _endpointChanged = false;
            await container
                .read(backgroundDownloadControllerProvider)
                .restartForEndpointChange();
            if (!_current) return;
          }
          if (!_initialized) {
            await _initialize(catalogId);
          } else {
            await pushPendingProgress(container);
            if (!_current) return;
            await _resume();
          }
          if (!_current) return;
        } catch (error, stack) {
          if (_current) debugPrint('Account startup failed: $error\n$stack');
        }
      } while ((_rerun || _offlineActivationPending) && _current);
    });
    _flight = work;
    return work.whenComplete(() {
      _flight = null;
      if ((_rerun || _offlineActivationPending) && _current) {
        unawaited(_request());
      }
    });
  }

  Future<void> _initialize(String catalogId) async {
    await recoverBulkMigrationsAtLaunch(container);
    if (!_current) return;
    try {
      await container.read(notificationsControllerProvider).sync();
    } catch (error) {
      if (_current) debugPrint('Notification startup failed: $error');
    }
    if (!_current || !_offlineActiveNow()) return;
    final runtime = container.read(offlineRuntimeStorageProvider.notifier);
    // Settle disk FIRST: launch reconcile and the catch-up must see
    // post-recovery device state, or overnight background downloads read as
    // missing and get re-fetched. Android reaches this through the worker's
    // replay; desktop/other has no replay, so it recovers here directly.
    if (isAndroidNative) {
      await runtime.track(
        () => container
            .read(backgroundDownloadControllerProvider)
            .replayAtLaunch(),
      );
      if (!_current) return;
    } else {
      await runtime.track(() => recoverDiskAtLaunch(container));
      if (!_current) return;
    }
    await pushPendingProgress(container);
    if (!_current) return;
    await reconcileAllAtLaunch(container);
    if (!_current) return;
    initChapterCatchUp(container);
    _catchupStarted = true;
    final preferences = container.read(sharedPreferencesProvider);
    final cleanupKey = 'offlinePhantomCleanupDone/$catalogId';
    if (preferences.getBool(cleanupKey) != true) {
      try {
        await runtime.track(() async {
          if (!_current) return;
          await container.read(offlineDatabaseProvider).purgeNonLibraryManga();
          if (!_current) return;
          await preferences.setBool(cleanupKey, true);
        });
      } catch (error) {
        if (_current) debugPrint('Account catalogue cleanup failed: $error');
      }
      if (!_current) return;
    }
    if (!isAndroidNative) {
      final db = container.read(offlineDatabaseProvider);
      final store = container.read(offlinePageStoreProvider);
      await runtime.track(() => recoverChaptersOnDisk(db: db, store: store));
      if (!_current) return;
    }
    _initialized = true;
    _endpointChanged = false;
    if (isAndroidNative) {
      await container
          .read(backgroundDownloadControllerProvider)
          .maybeStartAfterReplay();
    } else {
      await _resume();
    }
  }

  Future<void> _resume() async {
    if (!_current ||
        !_offlineActiveNow() ||
        !await resolvedDownloadPermissionAllowed(container.read)) {
      return;
    }
    if (isAndroidNative) {
      await container
          .read(offlineRuntimeStorageProvider.notifier)
          .track(
            () => container
                .read(backgroundDownloadControllerProvider)
                .replayAtLaunch(),
          );
      if (!_current ||
          !await resolvedDownloadPermissionAllowed(container.read)) {
        return;
      }
    }
    await reconcileAllAtLaunch(container);
    if (!_current || !await resolvedDownloadPermissionAllowed(container.read)) {
      return;
    }
    await runKeepRuleCatchUp(container);
    if (!_current || !await resolvedDownloadPermissionAllowed(container.read)) {
      return;
    }
    if (isAndroidNative) {
      await container
          .read(backgroundDownloadControllerProvider)
          .ensureServiceRunning(force: true);
    } else {
      final coordinator = container.read(offlineDownloadCoordinatorProvider);
      if (coordinator != null) {
        unawaited(
          coordinator.pumpDownloads().catchError((Object error) {
            if (_current) debugPrint('Account download resume failed: $error');
          }),
        );
      }
    }
  }

  /// Reads whether offline is active, for the pass running now: an
  /// activation that landed before this read is handled by this pass, so it
  /// no longer calls for another.
  bool _offlineActiveNow() {
    _offlineActivationPending = false;
    return container.read(offlineActiveProvider);
  }

  void _snapshot() {
    if (!_current || !_initialized || !container.read(offlineActiveProvider)) {
      return;
    }
    final runtime = container.read(offlineRuntimeStorageProvider.notifier);
    unawaited(
      runtime
          .track(() async {
            await writeCatchupWorkSpec(<T>(ProviderListenable<T> provider) {
              if (!_current) {
                throw StateError('Account session changed');
              }
              return container.read(provider);
            });
          })
          .catchError((Object error) {
            if (_current) debugPrint('Account work snapshot failed: $error');
          }),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    _subscriptions.clear();
    _lifecycle?.dispose();
    _background?.dispose();
    if (_catchupStarted) detachChapterCatchUp();
  }
}
