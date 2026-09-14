import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_actions.dart';
import 'package:tsumiru/src/features/account/data/account_notice.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/auth_state.dart';
import 'package:tsumiru/src/features/auth/presentation/reauth_banner.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/router_config.dart';

String _testToken() {
  final payload = jsonEncode({
    'exp':
        DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
        1000,
  });
  return 'e30.${base64Url.encode(utf8.encode(payload)).replaceAll('=', '')}.test-signature';
}

class _PasswordServer extends Link {
  _PasswordServer({required this.uncertain});
  final bool uncertain;
  bool failLogin = true;
  final operations = <String>[];
  final token = _testToken();

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final operation = request.operation.document.definitions
        .whereType<OperationDefinitionNode>()
        .single
        .name!
        .value;
    operations.add(operation);
    if (operation == 'SetAccountPassword' && uncertain) {
      throw const SocketException('password response unavailable');
    }
    if (operation == 'Login' && failLogin) {
      yield Response(
        response: {},
        errors: [const GraphQLError(message: 'Login unavailable')],
      );
      return;
    }
    final user = {
      '__typename': 'UserType',
      'id': 2,
      'username': 'Reader',
      'roles': ['USER'],
      'permissions': <String>[],
    };
    final payload = switch (operation) {
      'SetAccountPassword' => {
        'setPassword': {
          '__typename': 'SetPasswordPayload',
          'clientMutationId': null,
        },
      },
      'Login' => {
        'login': {
          '__typename': 'LoginPayload',
          'accessToken': token,
          'refreshToken': 'test-refresh',
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
              'value': 'notice-test-catalog',
            },
          ],
        },
      },
      _ => throw StateError('Unexpected test operation: $operation'),
    };
    yield Response(
      response: {},
      data: {
        '__typename': operation == 'Login' || operation == 'SetAccountPassword'
            ? 'Mutation'
            : 'Query',
        ...payload,
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late _PasswordServer server;

  ProviderContainer freshContainer() {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        unauthenticatedGraphQlClientProvider.overrideWithValue(
          GraphQLClient(link: server, cache: GraphQLCache()),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> failRotation(bool uncertain) async {
    server = _PasswordServer(uncertain: uncertain);
    SharedPreferences.setMockInitialValues({
      DBKeys.authType.name: AuthType.uiLogin.index,
      DBKeys.authUsername.name: 'Reader',
      DBKeys.serverUrl.name: 'http://server',
      DBKeys.serverExternalUrl.name: 'http://server',
      DBKeys.serverPort.name: 4567,
      DBKeys.serverPortToggle.name: true,
    });
    preferences = await SharedPreferences.getInstance();
    FlutterSecureStorage.setMockInitialValues({
      'auth.password': 'test-current-password',
      'auth.ui.accessToken': server.token,
      'auth.ui.refreshToken': 'test-refresh',
      'auth.ui.accountBinding': const AccountBinding(
        address: 'http://server:4567',
        userId: 2,
        username: 'Reader',
        catalogId: 'notice-test-catalog',
      ).encode(accessToken: server.token, refreshToken: 'test-refresh'),
    });
    final original = freshContainer();
    await original.read(authCredentialsStoreProvider.future);
    await expectLater(
      original
          .read(accountActionsProvider)
          .changePassword(
            currentPassword: 'test-current-password',
            newPassword: 'test-replacement-password',
          ),
      throwsA(
        uncertain
            ? isA<AccountPasswordUnconfirmed>()
            : isA<AccountPasswordSignInRequired>(),
      ),
    );
    expect(server.operations, ['SetAccountPassword', 'Login']);
    expect(
      original.read(authCredentialsStoreProvider).requireValue.uiAccessToken,
      isNull,
    );
    expect(
      original.read(authCredentialsStoreProvider).requireValue.accountBinding,
      isNull,
    );
    expect(original.read(needsReauthProvider), true);
    original.dispose();
  }

  Future<void> mountRoot(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.runAsync(
      () => container.read(authCredentialsStoreProvider.future),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => ReauthBannerHost(child: child!),
          home: const Scaffold(body: Text('Account root')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final uncertain in [false, true]) {
    testWidgets(
      '${uncertain ? 'unconfirmed' : 'confirmed'} password failure survives a fresh root and verified login clears it',
      (tester) async {
        await tester.runAsync(() => failRotation(uncertain));
        final restored = freshContainer();
        await tester.runAsync(
          () => restored.read(authCredentialsStoreProvider.future),
        );
        expect(restored.read(needsReauthProvider), false);
        expect(
          restored.read(accountNoticeProvider),
          uncertain
              ? AccountNoticeKind.passwordUnconfirmed
              : AccountNoticeKind.passwordSignInRequired,
        );
        await mountRoot(tester, restored);
        final expected = uncertain
            ? 'The password change could not be confirmed. Sign in again to continue.'
            : 'Sign in again to continue.';
        expect(find.byType(MaterialBanner), findsOneWidget);
        expect(find.text(expected), findsOneWidget);
        expect(
          find.text(
            uncertain
                ? 'Sign in again to continue.'
                : 'The password change could not be confirmed. Sign in again to continue.',
          ),
          findsNothing,
        );
        server.failLogin = false;
        await tester.runAsync(
          () => restored
              .read(authCoordinatorProvider.notifier)
              .loginUi(
                gqlClient: restored.read(unauthenticatedGraphQlClientProvider),
                username: 'Reader',
                password: 'test-replacement-password',
              ),
        );
        await tester.pumpAndSettle();
        expect(
          server.operations,
          containsAllInOrder([
            'Login',
            'AccountCapability',
            'CurrentAccount',
            'OfflineServerIdentity',
          ]),
        );
        expect(
          restored
              .read(authCredentialsStoreProvider)
              .requireValue
              .accountBinding
              ?.userId,
          2,
        );
        expect(restored.read(accountNoticeProvider), isNull);
        expect(find.byType(MaterialBanner), findsNothing);
        final afterSignIn = freshContainer();
        await mountRoot(tester, afterSignIn);
        expect(afterSignIn.read(accountNoticeProvider), isNull);
        expect(find.byType(MaterialBanner), findsNothing);
      },
    );
  }

  testWidgets(
    'notice follows configured external server and effective port across active LAN aliases',
    (tester) async {
      await tester.runAsync(() => failRotation(true));
      for (final scenario in [
        (
          external: 'http://server',
          active: 'http://192.168.1.20',
          port: 4567,
          addPort: true,
          visible: true,
        ),
        (
          external: 'http://server:4567',
          active: 'http://192.168.1.21',
          port: 9999,
          addPort: false,
          visible: true,
        ),
        (
          external: 'http://other',
          active: 'http://192.168.1.20',
          port: 4567,
          addPort: true,
          visible: false,
        ),
        (
          external: 'http://server',
          active: 'http://192.168.1.20',
          port: 4568,
          addPort: true,
          visible: false,
        ),
      ]) {
        await preferences.setString(
          DBKeys.serverExternalUrl.name,
          scenario.external,
        );
        await preferences.setString(DBKeys.serverUrl.name, scenario.active);
        await preferences.setInt(DBKeys.serverPort.name, scenario.port);
        await preferences.setBool(
          DBKeys.serverPortToggle.name,
          scenario.addPort,
        );
        final restored = freshContainer();
        await mountRoot(tester, restored);
        expect(
          restored.read(currentServerAddressProvider),
          contains('192.168.1.'),
        );
        expect(restored.read(needsReauthProvider), false);
        expect(
          find.byType(MaterialBanner),
          scenario.visible ? findsOneWidget : findsNothing,
          reason:
              '${scenario.external}, port=${scenario.port}, addPort=${scenario.addPort}',
        );
      }
    },
  );
}
