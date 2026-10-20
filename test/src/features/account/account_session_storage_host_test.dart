// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_session_storage.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/auth_session_transition.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_bootstrap.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_runtime_storage.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_storage_identity.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

class _Support extends PathProviderPlatform {
  _Support(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

const _a = AccountBinding(
  address: 'http://server',
  userId: 2,
  username: 'A',
  catalogId: 'A',
);

class _Fixture {
  _Fixture(this.preferences);
  final SharedPreferences preferences;
  late ProviderContainer active;
  int restarts = 0;
  int retained = 0;
  Completer<void>? recoveryStarted;
  Completer<void>? recoveryRelease;
  Object? recoveryError;
  bool serverAccess = false;
  String nonAccountServerId = 'basic-server';

  ProviderContainer create() => ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      accountStorageOpenerProvider.overrideWithValue(({
        accountId,
        legacyInstanceId,
        ownedRoot,
        accountOwner,
        recovery,
      }) async {
        if (recovery != null && recoveryStarted != null) {
          recoveryStarted!.complete();
          await recoveryRelease!.future;
          recovery.check();
          if (recoveryError != null) throw recoveryError!;
        }
        return initOfflineStorage(
          accountId: accountId,
          legacyInstanceId: legacyInstanceId,
          ownedRoot: ownedRoot,
          accountOwner: accountOwner,
          recovery: recovery,
        );
      }),
      currentServerAddressProvider.overrideWithValue('http://server'),
      offlineServerAccessProvider.overrideWith((ref) => serverAccess),
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
            nonAccountServerId,
      ),
    ],
  );

  static Future<_Fixture> open({
    bool legacy = false,
    bool partial = false,
  }) async {
    final root = await Directory.systemTemp.createTemp('session-storage-host-');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Support(root.path);
    addTearDown(() => PathProviderPlatform.instance = previous);
    FlutterSecureStorage.setMockInitialValues({
      'auth.ui.accessToken': 'A-access',
      'auth.ui.refreshToken': 'A-refresh',
      'auth.ui.accountBinding': _a.encode(
        accessToken: 'A-access',
        refreshToken: 'A-refresh',
      ),
    });
    SharedPreferences.setMockInitialValues({
      DBKeys.authType.name: AuthType.uiLogin.index,
    });
    final fixture = _Fixture(await SharedPreferences.getInstance());
    if (legacy) {
      final storage = (await initOfflineStorage())!;
      await storage.db.upsertMangaMetadata(
        id: 1,
        title: 'Legacy',
        updatedAt: DateTime(2026),
      );
      final pages = Directory(p.join(storage.paths.baseDir, '1', '7'));
      await pages.create(recursive: true);
      await File(p.join(pages.path, '000.jpg')).writeAsBytes([1, 2, 3]);
      await storage.db.close();
      if (partial) {
        final destination = File(
          p.join(storage.paths.baseDir, 'accounts', 'A', 'catalog.sqlite'),
        );
        await destination.parent.create(recursive: true);
        await File(
          p.join(storage.paths.baseDir, 'catalog.sqlite'),
        ).copy(destination.path);
      }
      await fixture.preferences.setString(
        DBKeys.offlineCatalogServerId.name,
        'A',
      );
      await fixture.preferences.setInt(
        DBKeys.offlineCatchUpWatermark.name,
        123,
      );
      await fixture.preferences.setStringList(
        DBKeys.offlineCatchUpAwaitingPull.name,
        ['1'],
      );
    }
    fixture.active = fixture.create();
    await fixture.active.read(authCredentialsStoreProvider.future);
    await fixture.active.read(accountSessionStorageProvider).restore();
    fixture.active
        .read(authCredentialsStoreProvider.notifier)
        .activateSession();
    return fixture;
  }

  Future<void> close() => active
      .read(offlineRuntimeStorageProvider.notifier)
      .replace(drain: () async {}, open: () async => null);
}

void main() {
  for (final mode in [AuthType.none, AuthType.basic]) {
    testWidgets(
      '${mode.name} downloads survive login and return without mismatch',
      (tester) async {
        await tester.runAsync(() async {
          final fixture = await _Fixture.open(legacy: true);
          final credentials = fixture.active.read(
            authCredentialsStoreProvider.notifier,
          );
          Future<void> leaveAccount() async {
            await credentials.withIdentityChange(() async {
              await credentials.clearUiLoginTokens();
              fixture.active.read(authTypeKeyProvider.notifier).update(mode);
            });
            credentials.activateSession();
            await fixture.active.read(serverInstanceIdProvider.future);
          }

          await leaveAccount();
          final storage = fixture.active.read(offlineRuntimeStorageProvider)!;
          fixture.serverAccess = true;
          fixture.active.invalidate(offlineServerAccessProvider);
          await fixture.active.read(offlineSyncProvider)!.onSynced!();
          fixture.serverAccess = false;
          fixture.active.invalidate(offlineServerAccessProvider);
          expect(
            fixture.preferences.getString(offlineNonAccountCatalogServerIdKey),
            'basic-server',
          );
          await storage.db.upsertMangaMetadata(
            id: 2,
            title: 'Saved without login',
            updatedAt: DateTime(2026),
          );
          final page = File(p.join(storage.paths.baseDir, '2', '8', '000.jpg'));
          await page.parent.create(recursive: true);
          await page.writeAsBytes([7, 8, 9]);
          await credentials.withIdentityChange(() async {
            fixture.active
                .read(authTypeKeyProvider.notifier)
                .update(AuthType.uiLogin);
            await credentials.saveUiLoginTokens(
              accessToken: 'return-A',
              refreshToken: 'return-refresh-A',
              binding: _a,
            );
          });
          credentials.activateSession();
          expect(
            fixture.preferences.getString(DBKeys.offlineCatalogServerId.name),
            'A',
          );
          expect(
            fixture.preferences.getString(offlineNonAccountCatalogServerIdKey),
            'basic-server',
          );
          await leaveAccount();
          expect(
            await fixture.active.read(offlineServerMismatchProvider.future),
            isNull,
          );
          expect(fixture.active.read(offlineActiveProvider), isTrue);
          final returned = fixture.active.read(offlineReadDatabaseProvider)!;
          expect((await returned.mangaById(2))?.title, 'Saved without login');
          expect(await page.readAsBytes(), [7, 8, 9]);
          fixture.nonAccountServerId = 'different-server';
          fixture.active.invalidate(serverInstanceIdProvider);
          fixture.active.invalidate(offlineServerMismatchProvider);
          final mismatch = await fixture.active.read(
            offlineServerMismatchProvider.future,
          );
          expect(mismatch?.catalogServer, 'basic-server');
          expect(
            fixture.preferences.getString(DBKeys.offlineCatalogServerId.name),
            'A',
          );
          expect(
            offlineCatalogServerIdKey(fixture.preferences),
            offlineNonAccountCatalogServerIdKey,
          );
          await fixture.close();
          fixture.active.dispose();
        });
      },
    );
  }

}
