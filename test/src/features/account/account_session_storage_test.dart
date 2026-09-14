import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_session_storage.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/auth_session_transition.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_runtime_storage.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

class _Support extends PathProviderPlatform {
  _Support(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'paused library subscriptions do not block account switches or sign-out',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'account-session-storage-',
      );
      PathProviderPlatform.instance = _Support(root.path);
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        DBKeys.authType.name: AuthType.uiLogin.index,
        DBKeys.offlineCatalogServerId.name: 'A',
        DBKeys.offlineCatchUpWatermark.name: 123,
        DBKeys.offlineCatchUpAwaitingPull.name: ['1'],
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authSessionTransitionProvider.overrideWith(
            (ref) => ref.read(accountSessionStorageProvider),
          ),
          serverInstanceIdProvider.overrideWith(
            (ref) async =>
                ref
                    .watch(authCredentialsStoreProvider)
                    .value
                    ?.accountBinding
                    ?.catalogId ??
                '',
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authCredentialsStoreProvider.future);
      final credentials = container.read(authCredentialsStoreProvider.notifier);
      final address = container.read(currentServerAddressProvider);
      for (final account in ['A', 'B', 'A']) {
        await credentials
            .saveUiLoginTokens(
              accessToken: '$account-access',
              refreshToken: '$account-refresh',
              binding: AccountBinding(
                address: address,
                userId: account == 'A' ? 1 : 2,
                username: account,
                catalogId: account,
              ),
            )
            .timeout(const Duration(seconds: 3));
        final storage = container.read(offlineRuntimeStorageProvider)!;
        expect(storage.paths.baseDir, endsWith('/accounts/$account'));
        expect(container.read(offlineDatabaseProvider), same(storage.db));
        expect(
          prefs.getInt('${DBKeys.offlineCatchUpWatermark.name}/$account'),
          account == 'A' ? 123 : null,
        );
        expect(
          prefs.getStringList(
            '${DBKeys.offlineCatchUpAwaitingPull.name}/$account',
          ),
          account == 'A' ? ['1'] : null,
        );
        final existing = await storage.db.mangaById(1);
        if (existing != null) expect(existing.title, account);
        await storage.db.upsertMangaMetadata(
          id: 1,
          title: account,
          updatedAt: DateTime(2026),
        );
        final subscriptions = [
          container.listen(offlineHasPendingProvider, (_, _) {}),
          container.listen(offlineChapterStateProvider(7), (_, _) {}),
          container.listen(offlineDeviceMangaIdsProvider, (_, _) {}),
          container.listen(mangaOfflineProgressProvider(1), (_, _) {}),
          container.listen(offlineChaptersForMangaProvider(1), (_, _) {}),
          container.listen(offlineSeriesProvider, (_, _) {}),
        ];
        await Future.wait([
          container.read(offlineHasPendingProvider.future),
          container.read(offlineChapterStateProvider(7).future),
          container.read(offlineDeviceMangaIdsProvider.future),
          container.read(mangaOfflineProgressProvider(1).future),
          container.read(offlineChaptersForMangaProvider(1).future),
          container.read(offlineSeriesProvider.future),
        ]);
        for (final subscription in subscriptions) {
          subscription.pause();
          addTearDown(subscription.close);
        }
      }
      await credentials
          .withIdentityChange(credentials.clearUiLoginTokens)
          .timeout(const Duration(seconds: 3));
      expect(container.read(offlineRuntimeStorageProvider), isNull);
      expect(container.read(offlineEnabledProvider), isFalse);
      for (final account in ['A', 'B']) {
        expect(
          File(
            '${root.path}/offline/accounts/$account/catalog.sqlite',
          ).existsSync(),
          isTrue,
        );
      }
    },
  );
}
