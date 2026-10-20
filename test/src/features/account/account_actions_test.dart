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
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
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

  test(
    'password change verifies settings, survives uncertain responses and '
    'retains credentials on rejection',
    () async {
      for (final uncertain in [false, true]) {
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
      }

      // Freshly verified settings permission is required.
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

      // An explicit rejection retains the previous credentials.
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
    },
  );

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
}
