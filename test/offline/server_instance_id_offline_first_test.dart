// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

/// resolve() never completes until [completer] is fired — simulates a slow or
/// unreachable network so the test can prove offline reads don't wait on it.
class _HangingRepo extends OfflineServerIdentityRepository {
  _HangingRepo() : super(_dummyClient());
  final completer = Completer<String>();
  final started = Completer<void>();
  int resolveCalls = 0;
  @override
  Future<String> resolve() {
    resolveCalls++;
    if (!started.isCompleted) started.complete();
    return completer.future;
  }
}

class _FixedRepo extends OfflineServerIdentityRepository {
  _FixedRepo(this._id) : super(_dummyClient());
  final String _id;
  @override
  Future<String> resolve() async => _id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'non-account offline identity survives an account cached at the same address',
    () async {
      const address = 'http://host:4567';
      SharedPreferences.setMockInitialValues({
        offlineNonAccountScopedKey: true,
        offlineNonAccountLastServerIdKey: 'basic-server',
        offlineNonAccountLastServerAddressKey: address,
        DBKeys.offlineLastServerId.name: 'login-account',
        DBKeys.offlineLastServerAddress.name: address,
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = _HangingRepo();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentServerAddressProvider.overrideWithValue(address),
          offlineServerIdentityRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(() {
        if (!repo.completer.isCompleted) {
          repo.completer.complete('basic-server');
        }
        c.dispose();
      });
      c.listen(serverInstanceIdProvider, (_, _) {});
      expect(
        await c
            .read(serverInstanceIdProvider.future)
            .timeout(const Duration(seconds: 2)),
        'basic-server',
      );
      await repo.started.future;
      repo.completer.complete('basic-server');
      await c.read(verifiedServerInstanceIdProvider.future);
      expect(prefs.getString(DBKeys.offlineLastServerId.name), 'login-account');
      expect(prefs.getString(offlineNonAccountLastServerIdKey), 'basic-server');
    },
  );

  test('serverInstanceId returns the cached id instantly for a known address, '
      'without waiting on the network (offline-first, #145 fix)', () async {
    const address = 'http://host:4567';
    SharedPreferences.setMockInitialValues({
      DBKeys.offlineLastServerId.name: 'cached-id',
      DBKeys.offlineLastServerAddress.name: address,
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = _HangingRepo();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentServerAddressProvider.overrideWith((ref) => address),
        offlineServerIdentityRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(() {
      if (!repo.completer.isCompleted) repo.completer.complete('late');
      c.dispose();
    });

    c.listen(serverInstanceIdProvider, (_, _) {});
    final id = await c
        .read(serverInstanceIdProvider.future)
        .timeout(const Duration(seconds: 2));

    expect(
      id,
      'cached-id',
      reason: 'must resolve from cache even though the network hangs',
    );
    await repo.started.future.timeout(const Duration(seconds: 2));
    expect(
      repo.resolveCalls,
      1,
      reason: 'the online verify still fires in the background',
    );
  });

  test(
    'serverInstanceId resolves online and caches on a first-seen address',
    () async {
      const address = 'http://new-server:4567';
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentServerAddressProvider.overrideWith((ref) => address),
          offlineServerIdentityRepositoryProvider.overrideWithValue(
            _FixedRepo('fresh-id'),
          ),
        ],
      );
      addTearDown(c.dispose);

      c.listen(serverInstanceIdProvider, (_, _) {});
      final id = await c.read(serverInstanceIdProvider.future);

      expect(id, 'fresh-id');
      expect(prefs.getString(DBKeys.offlineLastServerId.name), 'fresh-id');
      expect(prefs.getString(DBKeys.offlineLastServerAddress.name), address);
    },
  );

  const remoteUrl = 'https://remote.example';
  const lanUrl = 'http://192.168.2.4';
  const remoteAddress = 'https://remote.example:443';
  const lanAddress = 'http://192.168.2.4:80';

  Future<ProviderContainer> endpointContainer({
    required String active,
    required String cachedId,
    required String cachedAddress,
    required _HangingRepo repo,
  }) async {
    SharedPreferences.setMockInitialValues({
      DBKeys.serverUrl.name: active,
      DBKeys.serverExternalUrl.name: remoteUrl,
      DBKeys.serverLanUrl.name: lanUrl,
      DBKeys.serverPortToggle.name: false,
      DBKeys.offlineLastServerId.name: cachedId,
      DBKeys.offlineLastServerAddress.name: cachedAddress,
    });
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineServerIdentityRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(() {
      if (!repo.completer.isCompleted) repo.completer.complete('late');
      c.dispose();
    });
    return c;
  }

  test(
    'cached identity from the LAN address resolves while on the remote address',
    () async {
      final repo = _HangingRepo();
      final c = await endpointContainer(
        active: remoteUrl,
        cachedId: 'lan-cached-id',
        cachedAddress: lanAddress,
        repo: repo,
      );
      expect(c.read(currentServerAddressProvider), remoteAddress);

      c.listen(serverInstanceIdProvider, (_, _) {});
      expect(
        await c
            .read(serverInstanceIdProvider.future)
            .timeout(const Duration(seconds: 2)),
        'lan-cached-id',
      );
    },
  );

  test(
    'cached identity from the remote address resolves while on the LAN address',
    () async {
      final repo = _HangingRepo();
      final c = await endpointContainer(
        active: lanUrl,
        cachedId: 'remote-cached-id',
        cachedAddress: remoteAddress,
        repo: repo,
      );
      expect(c.read(currentServerAddressProvider), lanAddress);

      c.listen(serverInstanceIdProvider, (_, _) {});
      expect(
        await c
            .read(serverInstanceIdProvider.future)
            .timeout(const Duration(seconds: 2)),
        'remote-cached-id',
      );
    },
  );

  test('a cached identity from an unrelated address is not used', () async {
    final repo = _HangingRepo();
    final c = await endpointContainer(
      active: remoteUrl,
      cachedId: 'stranger-id',
      cachedAddress: 'http://203.0.113.9:80',
      repo: repo,
    );

    c.listen(serverInstanceIdProvider, (_, _) {});
    await expectLater(
      c
          .read(serverInstanceIdProvider.future)
          .timeout(const Duration(milliseconds: 300)),
      throwsA(isA<TimeoutException>()),
    );
  });
}
