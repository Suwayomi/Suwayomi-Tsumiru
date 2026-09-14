import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../auth/data/auth_session_transition.dart';
import '../../offline/data/account_storage_paths.dart';
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
          if (previousOwner != _owner() || (succeeded && current == null)) {
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

  Future<void> restore({String? ownedRoot}) async {
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
    final wasScoped = preferences.getBool(offlineAccountScopedKey) == true;
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
            final storage = await _ref.read(accountStorageOpenerProvider)(
              accountId: uiLogin ? binding!.catalogId : null,
              legacyInstanceId: preferences.getString(
                DBKeys.offlineCatalogServerId.name,
              ),
              ownedRoot: ownedRoot,
              accountOwner: uiLogin ? '${binding!.userId ?? 'legacy'}' : null,
            );
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
              storage != null && uiLogin,
            );
            return storage;
          },
        );
    _ref.invalidate(serverInstanceIdProvider);
    _ref.invalidate(offlineActiveProvider);
  }
}
