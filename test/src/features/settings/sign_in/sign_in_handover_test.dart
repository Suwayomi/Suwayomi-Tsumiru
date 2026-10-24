import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/auth_recovery_target.dart';
import 'package:tsumiru/src/features/auth/data/auth_state.dart';
import 'package:tsumiru/src/features/auth/data/custom_headers_store.dart';
import 'package:tsumiru/src/features/auth/data/pending_tracker_oauth_store.dart';
import 'package:tsumiru/src/features/auth/data/pending_tracker_oauth_store_stub.dart'
    as pending;
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/data/sign_in_actions.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/data/sign_in_executor.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/graphql/__generated__/sign_in.graphql.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

void main() {
  for (final loginWorks in [true, false]) {
    testWidgets('None to UI login handover: login succeeds $loginWorks', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        DBKeys.authType.name: AuthType.none.index,
      });
      FlutterSecureStorage.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      const before = SignInValues(
        mode: AuthType.none,
        username: 'admin',
        password: 'secret',
        audience: 'server',
        accessExpiry: 'PT5M',
        refreshExpiry: 'PT1440H',
      );
      final proposed = before.copyWith(mode: AuthType.uiLogin);
      var mode = 'NONE';
      final operations = <String>[];
      final transport = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final query = body['query'] as String;
        final operation = RegExp(
          r'(?:query|mutation) (\w+)',
        ).firstMatch(query)!.group(1)!;
        operations.add(operation);
        if (operation == 'SetSignInSettings') {
          mode = 'UI_LOGIN';
          await tester.pump();
        }
        if (operation == 'AccountCapability') {
          return http.Response(
            jsonEncode({
              'errors': [
                {
                  'message':
                      "Validation error (FieldUndefined@[user]) : Field 'user' in type 'Query' is undefined",
                },
              ],
            }),
            200,
          );
        }
        if (operation == 'Login' && !loginWorks) {
          return http.Response(
            jsonEncode({
              'errors': [
                {'message': 'Incorrect username or password.'},
              ],
            }),
            200,
          );
        }
        if (operation != 'SetSignInSettings' && operation != 'Login') {
          expect(request.headers['authorization'], 'Bearer access');
        }
        final settings = {
          '__typename': 'SettingsType',
          'authMode': mode,
          'authUsername': 'admin',
          'authPassword': 'secret',
          'jwtAudience': 'server',
          'jwtTokenExpiry': 'PT5M',
          'jwtRefreshExpiry': 'PT1440H',
        };
        final data = switch (operation) {
          'SetSignInSettings' => {
            'setSettings': {
              '__typename': 'SetSettingsPayload',
              'settings': settings,
            },
          },
          'SignInSettings' => {'settings': settings},
          'Login' => {
            'login': {
              '__typename': 'LoginPayload',
              'accessToken': 'access',
              'refreshToken': 'refresh',
            },
          },
          'OfflineServerIdentity' => {
            'metas': {
              '__typename': 'GlobalMetaNodeList',
              'nodes': [
                {
                  '__typename': 'GlobalMetaType',
                  'key': 'tsumiru_server_instance_id',
                  'value': 'catalogue',
                },
              ],
            },
          },
          _ => throw StateError(operation),
        };
        return http.Response(
          jsonEncode({
            'data': {
              '__typename': query.startsWith('mutation') ? 'Mutation' : 'Query',
              ...data,
            },
          }),
          200,
        );
      });
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          pendingTrackerOAuthStoreProvider.overrideWithValue(
            pending.createPendingTrackerOAuthStore(),
          ),
          unauthenticatedGraphQlClientProvider.overrideWithValue(
            GraphQLClient(
              link: HttpLink('http://localhost/graphql', httpClient: transport),
              cache: GraphQLCache(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(() async {
        await container.read(authCredentialsStoreProvider.future);
        await container.read(credentialsProvider.future);
        await container.read(customHttpHeadersProvider.future);
      });
      final store = container.read(authCredentialsStoreProvider.notifier);
      store.activateSession();
      final oldClient = container.read(graphQlClientProvider);
      late WidgetRef actionRef;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (_, ref, _) {
              if (!ref
                  .watch(settledAccountAccessProvider)
                  .allows(Enum$UserPermission.MANAGE_SETTINGS)) {
                return const SizedBox();
              }
              return Consumer(
                builder: (_, ref, _) {
                  actionRef = ref;
                  return const SizedBox();
                },
              );
            },
          ),
        ),
      );
      Object? failure;
      await tester.runAsync(() async {
        try {
          await SignInActions(actionRef).save(
            before: before,
            proposed: proposed,
            accounts: false,
            admin: true,
            web: true,
          );
        } catch (error) {
          failure = error;
        }
      });
      expect(mode, 'UI_LOGIN');
      if (loginWorks) {
        expect(failure, isNull);
        expect(container.read(authTypeKeyProvider), AuthType.uiLogin);
        expect(
          preferences.getInt(DBKeys.authType.name),
          AuthType.uiLogin.index,
        );
        expect(store.uiLoginTokens()?.accessToken, 'access');
        expect(store.uiLoginTokens()?.refreshToken, 'refresh');
        expect(container.read(needsReauthProvider), isFalse);
        expect(container.read(authRecoveryTargetProvider), isNull);
      } else {
        expect(failure, isNotNull);
        expect(container.read(authTypeKeyProvider), AuthType.none);
        expect(store.uiLoginTokens(), isNull);
        expect(container.read(authRecoveryTargetProvider), AuthType.uiLogin);
        await tester.runAsync(
          () => container
              .read(authModeReconcilerProvider)
              .reconcile(authFailure: true),
        );
        expect(container.read(authRecoveryTargetProvider), AuthType.uiLogin);
        expect(container.read(needsReauthProvider), isTrue);
      }
      final stale = await tester.runAsync(
        () => oldClient.query$ServerSignInStatus(
          Options$Query$ServerSignInStatus(fetchPolicy: FetchPolicy.noCache),
        ),
      );
      expect(
        stale!.exception?.linkException?.originalException,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Authentication session changed',
        ),
      );
      expect(operations, contains('Login'));
    });
  }
}
