import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_bootstrap.dart';
import 'package:tsumiru/src/features/account/data/account_session_storage.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/auth_session_transition.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_runtime_storage.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../helpers/offline_test_db.dart';

String _token(DateTime expiry) =>
    'e30.${base64Url.encode(utf8.encode(jsonEncode({'exp': expiry.millisecondsSinceEpoch ~/ 1000}))).replaceAll('=', '')}.signature';

class _Server extends Link {
  final operations = <String>[];
  bool offline = false;
  bool unknown = false;
  Completer<void>? refreshStarted;
  Completer<void>? refreshRelease;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final operation = request.operation.document.definitions
        .whereType<OperationDefinitionNode>()
        .single
        .name!
        .value;
    operations.add(operation);
    if (offline) throw const SocketException('offline');
    if (operation == 'RefreshToken') {
      refreshStarted?.complete();
      await refreshRelease?.future;
      yield Response(
        response: {},
        data: {
          '__typename': 'Mutation',
          'refreshToken': {
            '__typename': 'RefreshTokenPayload',
            'accessToken': _token(DateTime.now().add(const Duration(hours: 1))),
          },
        },
      );
    } else if (operation == 'OfflineServerIdentity') {
      yield Response(
        response: {},
        data: {
          '__typename': 'Query',
          'metas': {
            '__typename': 'MetaTypeConnection',
            'nodes': [
              {
                '__typename': 'GlobalMetaType',
                'key': 'tsumiru_server_instance_id',
                'value': 'account-root',
              },
            ],
          },
        },
      );
    } else {
      yield Response(
        response: {},
        data: {
          '__typename': 'Query',
          'user': unknown
              ? null
              : {
                  '__typename': 'UserType',
                  'id': 2,
                  'username': 'reader',
                  'roles': ['USER'],
                  'permissions': <String>[],
                },
        },
      );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Server server;
  late List<String?> opened;

  Future<void> setup({
    bool bound = false,
    bool expired = false,
    bool transition = false,
    AuthType mode = AuthType.uiLogin,
  }) async {
    final access = _token(
      DateTime.now().add(Duration(hours: expired ? -1 : 1)),
    );
    FlutterSecureStorage.setMockInitialValues({
      'auth.ui.accessToken': access,
      'auth.ui.refreshToken': 'original-refresh',
      if (bound)
        'auth.ui.accountBinding': const AccountBinding(
          address: 'https://external.test',
          userId: 2,
          username: 'reader',
          catalogId: 'account-root',
        ).encode(accessToken: access, refreshToken: 'original-refresh'),
    });
    SharedPreferences.setMockInitialValues({
      DBKeys.authUsername.name: 'reader',
    });
    server = _Server();
    opened = [];
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        authTypeKeyProvider.overrideWithValue(mode),
        currentServerAddressProvider.overrideWithValue('http://192.0.2.10'),
        unauthenticatedGraphQlClientProvider.overrideWithValue(
          GraphQLClient(link: server, cache: GraphQLCache()),
        ),
        if (transition)
          authSessionTransitionProvider.overrideWith(
            (ref) => ref.read(accountSessionStorageProvider),
          ),
        accountStorageOpenerProvider.overrideWithValue(({
          accountId,
          legacyInstanceId,
          ownedRoot,
          accountOwner,
        }) async {
          opened.add(accountId);
          if (transition) {
            final paths = OfflinePaths(
              (await Directory.systemTemp.createTemp(
                'account-bootstrap-',
              )).path,
            );
            final db = testOfflineDatabase();
            addTearDown(db.close);
            return (db: db, paths: paths, store: IoOfflinePageStore(paths));
          }
          return null;
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authCredentialsStoreProvider.future);
  }

  test(
    'bound offline account opens locally without login or refresh',
    () async {
      await setup(bound: true, expired: true);
      server.offline = true;
      await restoreAccountSession(container);
      expect(opened, ['account-root']);
      expect(server.operations, isEmpty);
    },
  );

  test('unbound account verifies ownership before opening storage', () async {
    await setup();
    await restoreAccountSession(container);
    expect(server.operations, [
      'AccountCapability',
      'CurrentAccount',
      'OfflineServerIdentity',
    ]);
    expect(opened, ['account-root']);
    final credentials = container
        .read(authCredentialsStoreProvider)
        .requireValue;
    expect(credentials.accountBinding?.userId, 2);
    expect(credentials.password, isNull);
  });

  test('expired unbound tokens refresh before verifying ownership', () async {
    await setup(expired: true);
    await restoreAccountSession(container);
    expect(server.operations, [
      'RefreshToken',
      'AccountCapability',
      'CurrentAccount',
      'OfflineServerIdentity',
    ]);
    expect(opened, ['account-root']);
    expect(
      container
          .read(authCredentialsStoreProvider)
          .requireValue
          .uiAccessTokenExpiresAt!
          .isAfter(DateTime.now()),
      isTrue,
    );
    expect(
      container.read(authCredentialsStoreProvider).requireValue.uiRefreshToken,
      'original-refresh',
    );
  });

  for (final failure in ['offline', 'unknown']) {
    test('$failure unbound account cannot adopt or open a catalogue', () async {
      await setup();
      server.offline = failure == 'offline';
      server.unknown = failure == 'unknown';
      await expectLater(restoreAccountSession(container), throwsA(anything));
      expect(opened, isEmpty);
      expect(container.read(offlineRuntimeStorageProvider), isNull);
      expect(
        container
            .read(authCredentialsStoreProvider)
            .requireValue
            .accountBinding,
        isNull,
      );
      expect(server.operations, ['AccountCapability']);
    });
  }

  test('switch during refresh rejects startup before account lookup', () async {
    await setup(expired: true);
    server.refreshStarted = Completer<void>();
    server.refreshRelease = Completer<void>();
    final restored = expectLater(
      restoreAccountSession(container),
      throwsStateError,
    );
    await server.refreshStarted!.future;
    await container
        .read(authCredentialsStoreProvider.notifier)
        .saveUiLoginTokens(
          accessToken: 'B-access',
          refreshToken: 'B-refresh',
          binding: const AccountBinding(
            address: 'http://192.0.2.10',
            userId: 3,
            username: 'B',
            catalogId: 'B-root',
          ),
        );
    server.refreshRelease!.complete();
    await restored;
    expect(server.operations, ['RefreshToken']);
    expect(opened, isEmpty);
    expect(
      container
          .read(authCredentialsStoreProvider)
          .requireValue
          .accountBinding
          ?.catalogId,
      'B-root',
    );
  });

  test('adoption transition opens native storage only once', () async {
    await setup(transition: true);
    await restoreAccountSession(container);
    expect(opened, ['account-root']);
    expect(container.read(offlineRuntimeStorageProvider), isNotNull);
  });

  test('legacy authentication opens the shared catalogue', () async {
    await setup(mode: AuthType.basic);
    await restoreAccountSession(container);
    expect(opened, [null]);
    expect(server.operations, isEmpty);
  });
}
