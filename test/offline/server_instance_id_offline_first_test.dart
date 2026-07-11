// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

/// resolve() never completes until [completer] is fired — simulates a slow or
/// unreachable network so the test can prove offline reads don't wait on it.
class _HangingRepo extends OfflineServerIdentityRepository {
  _HangingRepo() : super(_dummyClient());
  final completer = Completer<String>();
  int resolveCalls = 0;
  @override
  Future<String> resolve() {
    resolveCalls++;
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
  test(
      'serverInstanceId returns the cached id instantly for a known address, '
      'without waiting on the network (offline-first, #145 fix)', () async {
    const address = 'http://host:4567';
    SharedPreferences.setMockInitialValues({
      DBKeys.offlineLastServerId.name: 'cached-id',
      DBKeys.offlineLastServerAddress.name: address,
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = _HangingRepo();
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentServerAddressProvider.overrideWith((ref) => address),
      offlineServerIdentityRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(() {
      if (!repo.completer.isCompleted) repo.completer.complete('late');
      c.dispose();
    });

    final id = await c
        .read(serverInstanceIdProvider.future)
        .timeout(const Duration(seconds: 2));

    expect(id, 'cached-id',
        reason: 'must resolve from cache even though the network hangs');
    expect(repo.resolveCalls, 1,
        reason: 'the online verify still fires in the background');
  });

  test('serverInstanceId resolves online and caches on a first-seen address',
      () async {
    const address = 'http://new-server:4567';
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentServerAddressProvider.overrideWith((ref) => address),
      offlineServerIdentityRepositoryProvider
          .overrideWithValue(_FixedRepo('fresh-id')),
    ]);
    addTearDown(c.dispose);

    final id = await c.read(serverInstanceIdProvider.future);

    expect(id, 'fresh-id');
    expect(prefs.getString(DBKeys.offlineLastServerId.name), 'fresh-id');
    expect(prefs.getString(DBKeys.offlineLastServerAddress.name), address);
  });
}
