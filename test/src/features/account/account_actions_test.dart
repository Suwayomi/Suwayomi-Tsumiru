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
import 'package:tsumiru/src/features/account/data/account_actions.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/auth_state.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/login_credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

String _jwt(int hours) =>
    'e30.${base64Url.encode(utf8.encode(jsonEncode({'exp': DateTime.now().add(Duration(hours: hours)).millisecondsSinceEpoch ~/ 1000}))).replaceAll('=', '')}.signature';
String _operation(Request request) => request.operation.document.definitions
    .whereType<OperationDefinitionNode>()
    .single
    .name!
    .value;
String? _bearer(Request request) => request.context
    .entry<HttpLinkHeaders>()
    ?.headers
    .entries
    .where((entry) => entry.key.toLowerCase() == 'authorization')
    .firstOrNull
    ?.value;

class _Server extends Link {
  final requests = <Request>[];
  bool invalidCode = false;
  bool rejectPassword = false;
  bool losePasswordResponse = false;
  bool failLogin = false;
  int userId = 2;
  bool settingsPermission = true;
  bool rejectCurrentPassword = false;
  int pendingPasswordLogins = 0;
  bool changedPassword = false;
  int? confirmationUserId;
  String? confirmationCatalogId;
  Duration? delay;
  Set<String> delayedOperations = const {};
  String catalogId = 'canonical-root';
  final refreshedAccess = _jwt(2);
  final newAccess = _jwt(3);

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    requests.add(request);
    final operation = _operation(request);
    final input = request.variables['input'] as Map?;
    if (operation == 'Login' &&
        ((rejectCurrentPassword && input?['password'] == 'old-password') ||
            (changedPassword && pendingPasswordLogins-- > 0))) {
      yield Response(
        response: {},
        errors: [const GraphQLError(message: 'Rejected')],
      );
      return;
    }
    if ((invalidCode && operation.startsWith('Redeem')) ||
        (rejectPassword &&
            (operation == 'SetAccountPassword' ||
                operation == 'SetBuiltInAccountPassword')) ||
        (failLogin && operation == 'Login')) {
      yield Response(
        response: {},
        errors: [const GraphQLError(message: 'Rejected')],
      );
      return;
    }
    if (operation == 'SetBuiltInAccountPassword' ||
        operation == 'SetAccountPassword') {
      changedPassword = true;
    }
    if (losePasswordResponse &&
        (operation == 'SetAccountPassword' ||
            operation == 'SetBuiltInAccountPassword')) {
      throw const SocketException('response lost');
    }
    final mutation = ![
      'AccountCapability',
      'CurrentAccount',
      'OfflineServerIdentity',
    ].contains(operation);
    final user = {
      '__typename': 'UserType',
      'id': changedPassword ? confirmationUserId ?? userId : userId,
      'username': 'Canonical',
      'roles': ['USER'],
      'permissions': <String>[
        if (userId == 1 && settingsPermission) 'MANAGE_SETTINGS',
      ],
    };
    final payload = switch (operation) {
      'RedeemRegistrationCode' => {
        'redeemRegistrationCode': {
          '__typename': 'RedeemRegistrationCodePayload',
          'accessToken': newAccess,
          'refreshToken': 'new-refresh',
          'user': user,
        },
      },
      'RedeemRecoveryCode' => {
        'redeemRecoveryCode': {
          '__typename': 'RedeemRecoveryCodePayload',
          'accessToken': newAccess,
          'refreshToken': 'new-refresh',
          'user': user,
        },
      },
      'RefreshToken' => {
        'refreshToken': {
          '__typename': 'RefreshTokenPayload',
          'accessToken': refreshedAccess,
        },
      },
      'SetBuiltInAccountPassword' => {
        'setSettings': {
          '__typename': 'SetSettingsPayload',
          'clientMutationId': null,
        },
      },
      'SetAccountPassword' => {
        'setPassword': {
          '__typename': 'SetPasswordPayload',
          'clientMutationId': null,
        },
      },
      'Login' => {
        'login': {
          '__typename': 'LoginPayload',
          'accessToken': newAccess,
          'refreshToken': 'new-refresh',
        },
      },
      'AccountCapability' || 'CurrentAccount' => {'user': user},
      'OfflineServerIdentity' => {
        'metas': {
          '__typename': 'MetaTypeConnection',
          'nodes': [
            {
              '__typename': 'GlobalMetaType',
              'key': 'tsumiru_server_instance_id',
              'value': changedPassword
                  ? confirmationCatalogId ?? catalogId
                  : catalogId,
            },
          ],
        },
      },
      _ => throw StateError('Unexpected operation: $operation'),
    };
    if (delay != null &&
        (delayedOperations.isEmpty || delayedOperations.contains(operation))) {
      await Future<void>.delayed(delay!);
    }
    yield Response(
      response: {},
      data: {'__typename': mutation ? 'Mutation' : 'Query', ...payload},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Server server;
  late String oldAccess;

  Future<void> setup({
    bool expired = false,
    int userId = 2,
    String storedAddress = 'http://server',
    Duration? requestTimeout,
  }) async {
    oldAccess = _jwt(expired ? -1 : 1);
    FlutterSecureStorage.setMockInitialValues({
      'auth.password': 'old-password',
      'auth.simple.cookie': 'old-cookie',
      'auth.basic.credentials': 'old-basic',
      'auth.ui.accessToken': oldAccess,
      'auth.ui.refreshToken': 'old-refresh',
      'auth.ui.accountBinding': AccountBinding(
        address: storedAddress,
        userId: userId,
        username: 'Canonical',
        catalogId: 'canonical-root',
      ).encode(accessToken: oldAccess, refreshToken: 'old-refresh'),
    });
    SharedPreferences.setMockInitialValues({
      DBKeys.authType.name: AuthType.uiLogin.index,
      DBKeys.authUsername.name: 'old-label',
    });
    server = _Server()..userId = userId;
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        currentServerAddressProvider.overrideWithValue('http://server'),
        unauthenticatedGraphQlClientProvider.overrideWithValue(
          GraphQLClient(
            link: server,
            cache: GraphQLCache(),
            queryRequestTimeout: requestTimeout,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authCredentialsStoreProvider.future);
  }

  void expectRawAndBoundHeaders() {
    for (final request in server.requests) {
      final operation = _operation(request);
      if (operation == 'Login') {
        expect(request.variables['input'], {
          'username': 'Canonical',
          'password': 'new-password',
        });
      }
      if (operation == 'RefreshToken') {
        expect(request.variables['input'], {'refreshToken': 'old-refresh'});
      }
      if (operation.startsWith('Redeem') ||
          operation == 'Login' ||
          operation == 'RefreshToken') {
        expect(_bearer(request), isNull, reason: operation);
      } else if (operation == 'SetAccountPassword') {
        expect(
          _bearer(request),
          anyOf('Bearer $oldAccess', 'Bearer ${server.refreshedAccess}'),
        );
      } else {
        expect(
          _bearer(request),
          'Bearer ${server.newAccess}',
          reason: operation,
        );
      }
    }
  }

  for (final recovery in [false, true]) {
    test(
      recovery
          ? 'recovery adopts canonical identity using raw redemption'
          : 'registration adopts canonical identity using raw redemption',
      () async {
        await setup();
        await container
            .read(accountActionsProvider)
            .redeemCode(
              code: ' code ',
              username: recovery ? null : ' submitted ',
              password: 'new-password',
            );
        final state = container.read(authCredentialsStoreProvider).requireValue;
        expect(state.accountBinding?.username, 'Canonical');
        expect(state.accountBinding?.catalogId, 'canonical-root');
        expect(state.uiAccessToken, server.newAccess);
        expect(state.password, 'new-password');
        expect(state.simpleLoginCookie, isNull);
        expect(container.read(authUsernameProvider), 'Canonical');
        expect(container.read(authTypeKeyProvider), AuthType.uiLogin);
        expect(
          (server.requests.first.variables['input'] as Map)['code'],
          'code',
        );
        expectRawAndBoundHeaders();
      },
    );
  }

  for (final uncertain in [false, true]) {
    test(
      'built-in password verifies settings update with uncertain=$uncertain',
      () async {
        await setup(userId: 1);
        server.losePasswordResponse = uncertain;
        server.pendingPasswordLogins = 1;
        await container
            .read(accountActionsProvider)
            .changePassword(
              currentPassword: 'old-password',
              newPassword: 'new-password',
            );
        final operations = server.requests.map(_operation).toList();
        expect(operations.first, 'Login');
        expect(operations, contains('SetBuiltInAccountPassword'));
        expect(operations, isNot(contains('SetAccountPassword')));
        final update = server.requests.singleWhere(
          (r) => _operation(r) == 'SetBuiltInAccountPassword',
        );
        expect(update.variables['input'], {
          'settings': {'authPassword': 'new-password'},
        });
        expect(_bearer(update), 'Bearer ${server.newAccess}');
        expect(
          container.read(authCredentialsStoreProvider).requireValue.password,
          'new-password',
        );
      },
    );
  }

  test(
    'built-in password requires current password before settings mutation',
    () async {
      await setup(userId: 1);
      server.rejectCurrentPassword = true;
      await expectLater(
        container
            .read(accountActionsProvider)
            .changePassword(
              currentPassword: 'old-password',
              newPassword: 'new-password',
            ),
        throwsA(anything),
      );
      expect(server.requests.map(_operation), ['Login']);
      expect(
        container.read(authCredentialsStoreProvider).requireValue.password,
        'old-password',
      );
    },
  );

  test(
    'built-in password requires freshly verified settings permission',
    () async {
      await setup(userId: 1);
      server.settingsPermission = false;
      await expectLater(
        container
            .read(accountActionsProvider)
            .changePassword(
              currentPassword: 'old-password',
              newPassword: 'new-password',
            ),
        throwsA(anything),
      );
      expect(server.requests.map(_operation), ['Login', 'CurrentAccount']);
      expect(
        container.read(authCredentialsStoreProvider).requireValue.password,
        'old-password',
      );
    },
  );

  for (final password in ['', ' ', ' new-password', 'new-password\n']) {
    test(
      'built-in password rejects normalization: ${password.length}',
      () async {
        await setup(userId: 1);
        await expectLater(
          container
              .read(accountActionsProvider)
              .changePassword(
                currentPassword: 'old-password',
                newPassword: password,
              ),
          throwsA(isA<AccountPasswordWhitespace>()),
        );
        expect(server.requests, isEmpty);
        expect(
          container
              .read(authCredentialsStoreProvider)
              .requireValue
              .uiAccessToken,
          oldAccess,
        );
      },
    );
  }

  test(
    'built-in current password login must match the original account',
    () async {
      await setup(userId: 1);
      server.userId = 9;
      await expectLater(
        container
            .read(accountActionsProvider)
            .changePassword(
              currentPassword: 'old-password',
              newPassword: 'new-password',
            ),
        throwsStateError,
      );
      expect(server.requests.map(_operation), ['Login', 'CurrentAccount']);
      expect(
        container.read(authCredentialsStoreProvider).requireValue.uiAccessToken,
        oldAccess,
      );
    },
  );

  test('built-in explicit settings rejection retains credentials', () async {
    await setup(userId: 1);
    server.rejectPassword = true;
    await expectLater(
      container
          .read(accountActionsProvider)
          .changePassword(
            currentPassword: 'old-password',
            newPassword: 'new-password',
          ),
      throwsA(isA<OperationException>()),
    );
    expect(server.requests.map(_operation), [
      'Login',
      'CurrentAccount',
      'OfflineServerIdentity',
      'SetBuiltInAccountPassword',
    ]);
    expect(
      container.read(authCredentialsStoreProvider).requireValue.uiAccessToken,
      oldAccess,
    );
  });

  test(
    'built-in settings response alone never confirms a password change',
    () async {
      await setup(userId: 1);
      server.pendingPasswordLogins = 99;
      await expectLater(
        container
            .read(accountActionsProvider)
            .changePassword(
              currentPassword: 'old-password',
              newPassword: 'new-password',
            ),
        throwsA(isA<AccountPasswordUnconfirmed>()),
      );
      expect(
        server.requests.where((r) => _operation(r) == 'Login'),
        hasLength(7),
      );
      expect(
        server.requests.where(
          (r) => _operation(r) == 'SetBuiltInAccountPassword',
        ),
        hasLength(1),
      );
      expect(
        container.read(authCredentialsStoreProvider).requireValue.uiAccessToken,
        isNull,
      );
      expect(container.read(needsReauthProvider), isTrue);
    },
  );

  for (final builtIn in [false, true]) {
    for (final differentUser in [false, true]) {
      test(
        'password confirmation rejects changed identity before adoption: builtIn=$builtIn user=$differentUser',
        () async {
          await setup(userId: builtIn ? 1 : 2);
          if (differentUser) {
            server.confirmationUserId = 9;
          } else {
            server.confirmationCatalogId = 'different-root';
          }
          final seenUsers = <int?>[];
          final seenCatalogs = <String?>[];
          final subscription = container.listen(authCredentialsStoreProvider, (
            _,
            next,
          ) {
            seenUsers.add(next.value?.accountBinding?.userId);
            seenCatalogs.add(next.value?.accountBinding?.catalogId);
          });
          addTearDown(subscription.close);
          await expectLater(
            container
                .read(accountActionsProvider)
                .changePassword(
                  currentPassword: 'old-password',
                  newPassword: 'new-password',
                ),
            throwsA(
              builtIn
                  ? isA<AccountPasswordUnconfirmed>()
                  : isA<AccountPasswordSignInRequired>(),
            ),
          );
          expect(seenUsers, isNot(contains(9)));
          expect(seenCatalogs, isNot(contains('different-root')));
          expect(
            container
                .read(authCredentialsStoreProvider)
                .requireValue
                .uiAccessToken,
            isNull,
          );
        },
      );
    }
  }

  test(
    'built-in refuses a different server before password mutation',
    () async {
      await setup(userId: 1);
      server.catalogId = 'replacement-server';
      await expectLater(
        container
            .read(accountActionsProvider)
            .changePassword(
              currentPassword: 'old-password',
              newPassword: 'new-password',
            ),
        throwsStateError,
      );
      expect(server.requests.map(_operation), [
        'Login',
        'CurrentAccount',
        'OfflineServerIdentity',
      ]);
      expect(
        container.read(authCredentialsStoreProvider).requireValue.uiAccessToken,
        oldAccess,
      );
    },
  );

  test('invalid registration code preserves the previous account', () async {
    await setup();
    server.invalidCode = true;
    await expectLater(
      container
          .read(accountActionsProvider)
          .redeemCode(code: 'bad', username: 'new', password: 'new-password'),
      throwsA(anything),
    );
    final state = container.read(authCredentialsStoreProvider).requireValue;
    expect(state.uiAccessToken, oldAccess);
    expect(state.password, 'old-password');
    expect(state.accountBinding?.catalogId, 'canonical-root');
    expect(server.requests.map(_operation), ['RedeemRegistrationCode']);
    expectRawAndBoundHeaders();
  });

  test(
    'sign-out clears credentials and retains auth mode and catalogue files',
    () async {
      await setup();
      final root = await Directory.systemTemp.createTemp('account-signout-');
      final catalogue = File('${root.path}/catalog.sqlite');
      await catalogue.writeAsBytes([1, 2, 3]);
      await container.read(accountActionsProvider).signOut();
      final state = container.read(authCredentialsStoreProvider).requireValue;
      expect(state.uiAccessToken, isNull);
      expect(state.uiRefreshToken, isNull);
      expect(state.accountBinding, isNull);
      expect(state.password, isNull);
      expect(state.simpleLoginCookie, isNull);
      expect(
        await const FlutterSecureStorage().read(key: 'auth.basic.credentials'),
        isNull,
      );
      expect(container.read(authTypeKeyProvider), AuthType.uiLogin);
      expect(await catalogue.readAsBytes(), [1, 2, 3]);
      expect(server.requests, isEmpty);
    },
  );

  test(
    'expired access refreshes before password rotation and new login',
    () async {
      await setup(expired: true);
      await container
          .read(accountActionsProvider)
          .changePassword(
            currentPassword: 'old-password',
            newPassword: 'new-password',
          );
      expect(server.requests.map(_operation), [
        'RefreshToken',
        'SetAccountPassword',
        'Login',
        'AccountCapability',
        'CurrentAccount',
        'OfflineServerIdentity',
      ]);
      expect(_bearer(server.requests[1]), 'Bearer ${server.refreshedAccess}');
      final state = container.read(authCredentialsStoreProvider).requireValue;
      expect(state.uiAccessToken, server.newAccess);
      expect(state.password, 'new-password');
      expect(state.accountBinding?.username, 'Canonical');
      expectRawAndBoundHeaders();
    },
  );

  test('a password change survives an endpoint switch', () async {
    // The endpoint resolver rewrites the server URL on a Wi-Fi/mobile switch,
    // so the stored binding holds the address login used, not the current one.
    await setup(storedAddress: 'http://lan-server');
    await container
        .read(accountActionsProvider)
        .changePassword(
          currentPassword: 'old-password',
          newPassword: 'new-password',
        );
    final state = container.read(authCredentialsStoreProvider).requireValue;
    expect(state.password, 'new-password');
    expect(state.accountBinding?.username, 'Canonical');
    expect(state.accountBinding?.address, 'http://server');
  });

  test('account verification honours the configured request timeout', () async {
    // The verification client is built from the parent's link, so it must
    // carry the parent's timeout. Left to graphql's own default it would wait
    // five seconds and this slow response would pass unnoticed.
    await setup(requestTimeout: const Duration(milliseconds: 50));
    // Only the post-rotation verification is slow, so the parent client's own
    // requests still succeed and the failure can only come from the child.
    server.delayedOperations = const {'AccountCapability', 'CurrentAccount'};
    server.delay = const Duration(milliseconds: 400);
    await expectLater(
      container
          .read(accountActionsProvider)
          .changePassword(
            currentPassword: 'old-password',
            newPassword: 'new-password',
          ),
      throwsA(isA<Object>()),
    );
  });

  test('explicit password rejection retains old credentials', () async {
    await setup();
    server.rejectPassword = true;
    await expectLater(
      container
          .read(accountActionsProvider)
          .changePassword(
            currentPassword: 'wrong',
            newPassword: 'new-password',
          ),
      throwsA(isA<OperationException>()),
    );
    expect(
      container.read(authCredentialsStoreProvider).requireValue.uiAccessToken,
      oldAccess,
    );
    expect(
      container.read(authCredentialsStoreProvider).requireValue.password,
      'old-password',
    );
    expect(server.requests.map(_operation), ['SetAccountPassword']);
    expectRawAndBoundHeaders();
  });

  test(
    'lost password response recovers by signing in with the new password',
    () async {
      await setup();
      server.losePasswordResponse = true;
      await container
          .read(accountActionsProvider)
          .changePassword(
            currentPassword: 'old-password',
            newPassword: 'new-password',
          );
      expect(
        container.read(authCredentialsStoreProvider).requireValue.uiAccessToken,
        server.newAccess,
      );
      expect(
        container.read(authCredentialsStoreProvider).requireValue.password,
        'new-password',
      );
      expectRawAndBoundHeaders();
    },
  );

  for (final uncertain in [false, true]) {
    test(
      uncertain
          ? 'uncertain rotation and failed login clears session with unconfirmed error'
          : 'confirmed rotation and failed login clears session with sign-in error',
      () async {
        await setup();
        server.losePasswordResponse = uncertain;
        server.failLogin = true;
        await expectLater(
          container
              .read(accountActionsProvider)
              .changePassword(
                currentPassword: 'old-password',
                newPassword: 'new-password',
              ),
          throwsA(
            uncertain
                ? isA<AccountPasswordUnconfirmed>()
                : isA<AccountPasswordSignInRequired>(),
          ),
        );
        final state = container.read(authCredentialsStoreProvider).requireValue;
        expect(state.uiAccessToken, isNull);
        expect(state.uiRefreshToken, isNull);
        expect(state.accountBinding, isNull);
        expect(state.password, isNull);
        expect(container.read(needsReauthProvider), isTrue);
        expectRawAndBoundHeaders();
      },
    );
  }
}
