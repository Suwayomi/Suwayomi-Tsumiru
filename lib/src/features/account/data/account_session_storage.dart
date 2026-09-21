// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../auth/data/auth_session_transition.dart';
import '../../offline/data/account_storage_paths.dart';
import '../../offline/data/account_storage_recovery.dart';
import '../../offline/data/account_storage_recovery_state.dart';
import '../../offline/data/background/background_download_controller_shim.dart';
import '../../offline/data/offline_background_downloads.dart';
import '../../offline/data/offline_bootstrap.dart';
import '../../offline/data/offline_chapter_catchup.dart';
import '../../offline/data/offline_download_coordinator.dart';
import '../../offline/data/offline_download_providers.dart';
import '../../offline/data/offline_repository.dart';
import '../../offline/data/offline_runtime_storage.dart';
import '../../offline/data/offline_server_identity_repository.dart';

typedef AccountStorageOpener =
    Future<OfflineStorage?> Function({
      String? accountId,
      String? legacyInstanceId,
      String? ownedRoot,
      String? accountOwner,
      AccountStorageRecovery? recovery,
    });

final accountStorageOpenerProvider = Provider<AccountStorageOpener>(
  (ref) => initOfflineStorage,
);
final accountSessionStorageProvider = Provider<AccountSessionStorage>(
  AccountSessionStorage.new,
);

class AccountSessionStorage implements AuthSessionTransition {
  AccountSessionStorage(this._ref);
  final Ref _ref;
  Future<void>? _recoveryFlight;
  bool Function()? _recoveryIsCurrent;

  Future<void> recover({Map<int, bool> progressChoices = const {}}) {
    if (_recoveryFlight != null) return _recoveryFlight!;
    if (_ref.read(accountStorageRecoveryProvider) == null) {
      return Future.value();
    }
    final current = _ref
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    _recoveryIsCurrent = current;
    final status = _ref.read(accountStorageRecoveryProvider.notifier);
    final work = Future<void>(() async {
      if (!_ref.mounted || !current()) return;
      status.update(
        const AccountStorageRecoveryState(
          AccountStorageRecoveryPhase.recovering,
        ),
      );
      try {
        await restore(
          recovery: AccountStorageRecovery(
            progressChoices: progressChoices,
            isCurrent: () => _ref.mounted && current(),
            onProgress: (completed) => status.update(
              AccountStorageRecoveryState(
                AccountStorageRecoveryPhase.recovering,
                completed: completed,
              ),
            ),
          ),
        );
        if (_ref.mounted && current()) {
          await _ref.read(backgroundDownloadControllerProvider).rebindStorage();
        }
      } catch (error, stack) {
        debugPrint('Offline storage recovery failed: $error\n$stack');
        if (current()) {
          status.update(
            AccountStorageRecoveryState(
              AccountStorageRecoveryPhase.failed,
              conflicts: error is AccountStorageProgressConflict
                  ? error.conflicts
                  : const [],
              details: error is AccountStorageProgressConflict
                  ? null
                  : error.toString(),
            ),
          );
        }
      }
    });
    _recoveryFlight = work;
    return work.whenComplete(() {
      _recoveryFlight = null;
      _recoveryIsCurrent = null;
    });
  }

  @override
  Future<T> run<T>(Future<T> Function() action) async {
    final background = _ref.read(backgroundDownloadControllerProvider);
    return background.changeIdentity(() async {
      final previousOwner = _owner();
      final current = _ref.read(offlineRuntimeStorageProvider);
      final runtime = _ref.read(offlineRuntimeStorageProvider.notifier);
      final coordinator = current == null
          ? null
          : _ref.read(offlineDownloadCoordinatorProvider);
      coordinator?.pause();
      detachChapterCatchUp();
      await background.detachStorage();
      try {
        await OfflineDownloadCoordinator.stopAll();
        await runtime.drain();
        resetChapterCatchUp();
        var succeeded = false;
        try {
          final result = await action();
          succeeded = true;
          return result;
        } finally {
          final interruptedRecovery =
              current == null &&
              (_recoveryFlight != null ||
                  _ref.read(accountStorageRecoveryProvider)?.phase ==
                      AccountStorageRecoveryPhase.recovering);
          if (previousOwner != _owner() ||
              (succeeded && current == null) ||
              interruptedRecovery) {
            await restore(ownedRoot: background.ownedStorageRoot);
          }
        }
      } finally {
        await background.rebindStorage();
      }
    });
  }

  Object _owner() {
    final mode = _ref.read(authTypeKeyProvider);
    final binding = _ref
        .read(authCredentialsStoreProvider)
        .value
        ?.accountBinding;
    return (
      mode,
      mode == AuthType.uiLogin
          ? binding?.catalogId
          : _ref.read(currentServerAddressProvider),
      mode == AuthType.uiLogin ? binding?.userId : null,
    );
  }

  Future<void> restore({
    String? ownedRoot,
    AccountStorageRecovery? recovery,
  }) async {
    if (recovery == null) {
      final flight = _recoveryFlight;
      final recoveryIsCurrent = _recoveryIsCurrent;
      await flight;
      if (flight != null && recoveryIsCurrent?.call() == true) return;
      _ref.read(accountStorageRecoveryProvider.notifier).update(null);
    }
    final preferences = _ref.read(sharedPreferencesProvider);
    final binding = _ref
        .read(authCredentialsStoreProvider)
        .value
        ?.accountBinding;
    final uiLogin = _ref.read(authTypeKeyProvider) == AuthType.uiLogin;
    final address = _ref.read(currentServerAddressProvider);
    final canOpen = !uiLogin || binding != null;
    final legacyOwner = preferences.getString(
      DBKeys.offlineCatalogServerId.name,
    );
    final wasScoped =
        preferences.getBool(offlineAccountScopedKey) == true ||
        preferences.getBool(offlineNonAccountScopedKey) == true;
    await _ref
        .read(offlineRuntimeStorageProvider.notifier)
        .replace(
          drain: () async {},
          onDetached: () {
            // Paused route subscriptions otherwise prevent Drift from closing.
            _ref.invalidate(offlineHasPendingProvider);
            _ref.invalidate(offlineChapterStateProvider);
            _ref.invalidate(offlineDeviceMangaIdsProvider);
            _ref.invalidate(mangaOfflineProgressProvider);
            _ref.invalidate(offlineChaptersForMangaProvider);
            _ref.invalidate(offlineSeriesProvider);
          },
          open: () async {
            if (!canOpen) return null;
            OfflineStorage? storage;
            try {
              storage = await _ref.read(accountStorageOpenerProvider)(
                accountId: uiLogin ? binding!.catalogId : null,
                legacyInstanceId: preferences.getString(
                  DBKeys.offlineCatalogServerId.name,
                ),
                ownedRoot: ownedRoot,
                accountOwner: uiLogin ? '${binding!.userId ?? 'legacy'}' : null,
                recovery: recovery,
              );
            } on AccountStorageRecoveryRequired {
              _ref
                  .read(accountStorageRecoveryProvider.notifier)
                  .update(
                    const AccountStorageRecoveryState(
                      AccountStorageRecoveryPhase.pending,
                    ),
                  );
              return null;
            } catch (error, stack) {
              if (recovery != null) rethrow;
              debugPrint('Offline storage could not open: $error\n$stack');
              _ref
                  .read(accountStorageRecoveryProvider.notifier)
                  .update(
                    AccountStorageRecoveryState(
                      AccountStorageRecoveryPhase.failed,
                      details: error.toString(),
                    ),
                  );
              return null;
            }
            try {
              recovery?.check();
            } catch (_) {
              await storage?.db.close();
              rethrow;
            }
            if (storage != null && uiLogin) {
              await preferences.setString(
                'account.catalogue/${binding!.catalogId}',
                jsonEncode({
                  'username': binding.username,
                  'address': binding.address,
                }),
              );
              if (!wasScoped &&
                  legacyOwner == binding.catalogId &&
                  !await accountStorageWasCleared(storage.paths)) {
                final watermarkKey =
                    '${DBKeys.offlineCatchUpWatermark.name}/${binding.catalogId}';
                final watermark = preferences.getInt(
                  DBKeys.offlineCatchUpWatermark.name,
                );
                if (watermark != null &&
                    !preferences.containsKey(watermarkKey)) {
                  await preferences.setInt(watermarkKey, watermark);
                }
                final awaitingKey =
                    '${DBKeys.offlineCatchUpAwaitingPull.name}/${binding.catalogId}';
                final awaiting = preferences.getStringList(
                  DBKeys.offlineCatchUpAwaitingPull.name,
                );
                if (awaiting != null && !preferences.containsKey(awaitingKey)) {
                  await preferences.setStringList(awaitingKey, awaiting);
                }
              }
              await preferences.setString(
                DBKeys.offlineCatalogServerId.name,
                binding.catalogId,
              );
              await preferences.setString(
                DBKeys.offlineLastServerId.name,
                binding.catalogId,
              );
              await preferences.setString(
                DBKeys.offlineLastServerAddress.name,
                address,
              );
            }
            await preferences.setBool(
              offlineAccountScopedKey,
              storage != null && isAccountStoragePath(storage.paths.baseDir),
            );
            await preferences.setBool(
              offlineNonAccountScopedKey,
              storage != null && isNonAccountStoragePath(storage.paths.baseDir),
            );
            _ref.read(accountStorageRecoveryProvider.notifier).update(null);
            return storage;
          },
        );
    _ref.invalidate(serverInstanceIdProvider);
    _ref.invalidate(offlineActiveProvider);
  }
}
