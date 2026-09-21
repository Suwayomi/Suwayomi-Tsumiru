// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_bootstrap.dart';
import 'package:tsumiru/src/features/account/data/account_session_startup.dart';
import 'package:tsumiru/src/features/account/data/account_session_storage.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_recovery_state.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/features/offline/data/server_reachability.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

class _Endpoint extends ServerEndpointResolver {
  @override
  String? build() => 'http://server';
}

class _SlowRecovery extends AccountSessionStorage {
  _SlowRecovery(super.ref);
  final entered = Completer<void>();
  final released = Completer<void>();
  @override
  Future<void> recover({Map<int, bool> progressChoices = const {}}) {
    if (!entered.isCompleted) entered.complete();
    return released.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'startup verifies the server while storage recovery is still running',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final probed = Completer<void>();
      late _SlowRecovery recovery;
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          authTypeKeyProvider.overrideWithValue(AuthType.none),
          serverEndpointResolverProvider.overrideWith(_Endpoint.new),
          currentServerAddressProvider.overrideWithValue('http://server'),
          offlineActiveProvider.overrideWithValue(false),
          accountSessionStorageProvider.overrideWith(
            (ref) => recovery = _SlowRecovery(ref),
          ),
          verifiedServerInstanceIdProvider.overrideWith((ref) async {
            if (!probed.isCompleted) probed.complete();
            throw const SocketException('offline');
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authCredentialsStoreProvider.future);
      container
          .read(accountStorageRecoveryProvider.notifier)
          .update(
            const AccountStorageRecoveryState(
              AccountStorageRecoveryPhase.pending,
            ),
          );
      container.read(accountSessionStorageProvider);
      addTearDown(() {
        if (!recovery.released.isCompleted) recovery.released.complete();
      });
      final startup = AccountSessionStartup(container);
      addTearDown(startup.dispose);
      final started = startup.start();
      await recovery.entered.future;
      await probed.future.timeout(const Duration(seconds: 1));
      expect(recovery.released.isCompleted, isFalse);
      await started;
    },
  );

  test('offline upgrade verifies the stored account on reconnect', () async {
    FlutterSecureStorage.setMockInitialValues({
      'auth.ui.accessToken': 'stored-access',
      'auth.ui.refreshToken': 'stored-refresh',
    });
    SharedPreferences.setMockInitialValues({});
    var offline = true;
    final requests = <String>[];
    final opened = Completer<String?>();
    final client = GraphQLClient(
      cache: GraphQLCache(),
      link: Link.function((request, [forward]) async* {
        final operation = request.operation.document.definitions
            .whereType<OperationDefinitionNode>()
            .single
            .name!
            .value;
        requests.add(operation);
        if (offline) throw const SocketException('offline');
        yield Response(
          response: {},
          data: {
            '__typename': 'Query',
            if (operation == 'OfflineServerIdentity')
              'metas': {
                '__typename': 'MetaTypeConnection',
                'nodes': [
                  {
                    '__typename': 'GlobalMetaType',
                    'key': 'tsumiru_server_instance_id',
                    'value': 'reader-catalogue',
                  },
                ],
              }
            else
              'user': {
                '__typename': 'UserType',
                'id': 2,
                'username': 'reader',
                'roles': ['USER'],
                'permissions': <String>[],
              },
          },
        );
      }),
    );
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        authTypeKeyProvider.overrideWithValue(AuthType.uiLogin),
        serverEndpointResolverProvider.overrideWith(_Endpoint.new),
        currentServerAddressProvider.overrideWithValue('http://server'),
        unauthenticatedGraphQlClientProvider.overrideWithValue(client),
        graphQlClientProvider.overrideWithValue(client),
        offlineActiveProvider.overrideWithValue(false),
        accountStorageOpenerProvider.overrideWithValue(({
          accountId,
          legacyInstanceId,
          ownedRoot,
          accountOwner,
          recovery,
        }) async {
          opened.complete(accountId);
          return null;
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authCredentialsStoreProvider.future);
    await expectLater(restoreAccountSession(container), throwsA(anything));
    final startup = AccountSessionStartup(container);
    addTearDown(startup.dispose);
    await startup.start();
    expect(
      container.read(authCredentialsStoreProvider).requireValue.accountBinding,
      isNull,
    );
    expect(requests, ['AccountCapability']);
    container.read(serverUnreachableProvider.notifier).set(true);
    offline = false;
    requests.clear();
    container.read(serverUnreachableProvider.notifier).set(false);
    expect(
      await opened.future.timeout(const Duration(seconds: 1)),
      'reader-catalogue',
    );
    expect(
      container
          .read(authCredentialsStoreProvider)
          .requireValue
          .accountBinding
          ?.userId,
      2,
    );
    expect(requests, [
      'AccountCapability',
      'CurrentAccount',
      'OfflineServerIdentity',
    ]);
  });

  for (final bound in [false, true]) {
    test(
      bound
          ? 'bound reconnect does not reopen storage'
          : 'signed-out reconnect does not open storage',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          if (bound) ...{
            'auth.ui.accessToken': 'access',
            'auth.ui.refreshToken': 'refresh',
            'auth.ui.accountBinding': const AccountBinding(
              address: 'http://server',
              userId: 2,
              username: 'reader',
              catalogId: 'root',
            ).encode(accessToken: 'access', refreshToken: 'refresh'),
          },
        });
        SharedPreferences.setMockInitialValues({});
        var restores = 0;
        var probes = 0;
        final retried = Completer<void>();
        final container = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
            authTypeKeyProvider.overrideWithValue(AuthType.uiLogin),
            serverEndpointResolverProvider.overrideWith(_Endpoint.new),
            currentServerAddressProvider.overrideWithValue('http://server'),
            offlineActiveProvider.overrideWithValue(false),
            verifiedServerInstanceIdProvider.overrideWith((ref) async {
              if (++probes == 2) retried.complete();
              throw const SocketException('offline');
            }),
            accountStorageOpenerProvider.overrideWithValue(({
              accountId,
              legacyInstanceId,
              ownedRoot,
              accountOwner,
              recovery,
            }) async {
              restores++;
              return null;
            }),
          ],
        );
        addTearDown(container.dispose);
        await container.read(authCredentialsStoreProvider.future);
        container.read(serverUnreachableProvider.notifier).set(true);
        final startup = AccountSessionStartup(container);
        addTearDown(startup.dispose);
        await startup.start();
        container.read(serverUnreachableProvider.notifier).set(false);
        if (bound) {
          await retried.future.timeout(const Duration(seconds: 1));
          expect(probes, 2);
        } else {
          await Future<void>.delayed(Duration.zero);
          expect(probes, 0);
        }
        expect(restores, 0);
      },
    );
  }
}
