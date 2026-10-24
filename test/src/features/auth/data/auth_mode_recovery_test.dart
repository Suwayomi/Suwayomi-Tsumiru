import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/auth_recovery_target.dart';
import 'package:tsumiru/src/features/auth/data/auth_state.dart';
import 'package:tsumiru/src/features/auth/data/suwayomi_auth_link.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/graphql/__generated__/sign_in.graphql.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/utils/network/graphql_errors.dart';

import 'recorded_auth_response.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final manager in [false, true]) {
    for (final refused in [false, true]) {
      test(
        'recovery preserves credentials: manager $manager, protected read $refused',
        () async {
          FlutterSecureStorage.setMockInitialValues({});
          SharedPreferences.setMockInitialValues({
            DBKeys.authType.name: AuthType.uiLogin.index,
          });
          final client = recordedAuthClient(
            refused ? 401 : 200,
            refused
                ? '{"errors":[{"message":"Unauthorized"}]}'
                : '{"data":{"__typename":"Query","settings":{"__typename":"SettingsType","authMode":"NONE","jwtAudience":"server"}}}',
          );
          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(
                await SharedPreferences.getInstance(),
              ),
              unauthenticatedGraphQlClientProvider.overrideWithValue(client),
              settledAccountAccessProvider.overrideWithValue(
                AccountAccess(
                  capability: AccountCapability.supported,
                  user: Fragment$AccountDto(
                    id: 2,
                    username: 'reader',
                    roles: const [],
                    permissions: manager
                        ? const [Enum$UserPermission.MANAGE_SETTINGS]
                        : const [],
                  ),
                ),
              ),
            ],
          );
          addTearDown(container.dispose);
          await container.read(authCredentialsStoreProvider.future);
          await container.read(credentialsProvider.future);
          final store = container.read(authCredentialsStoreProvider.notifier);
          await store.saveUiLoginTokens(
            accessToken: 'old',
            refreshToken: 'refresh',
          );
          store.activateSession();
          final epoch = store.sessionEpoch;
          await container.read(authModeReconcilerProvider).reconcile();
          expect(container.read(authRecoveryTargetProvider), isNull);
          await container
              .read(authModeReconcilerProvider)
              .reconcile(authFailure: true);
          expect(
            container.read(authRecoveryTargetProvider),
            manager && !refused ? AuthType.none : AuthType.uiLogin,
          );
          expect(container.read(needsReauthProvider), isTrue);
          expect(container.read(authTypeKeyProvider), AuthType.uiLogin);
          expect(store.uiLoginTokens()?.accessToken, 'old');
          expect(store.sessionEpoch, epoch);
          container
              .read(authRecoveryTargetProvider.notifier)
              .set(AuthType.uiLogin);
          await container
              .read(authModeReconcilerProvider)
              .reconcile(authFailure: true);
          expect(container.read(authRecoveryTargetProvider), AuthType.uiLogin);
        },
      );
    }
  }
  for (final response in [
    (
      200,
      '{"errors":[{"message":"Exception while fetching data (/settings) : Unauthorized"}]}',
    ),
    (200, '{"errors":[{"message":"Visitor"}]}'),
    (401, 'Unauthorized'),
    (400, 'Token intended for different audience [old]'),
    (500, 'Server error'),
  ]) {
    test('HTTP decoder classifies ${response.$1} ${response.$2}', () async {
      var recoveryRequested = false;
      final raw = recordedAuthClient(response.$1, response.$2);
      final client = GraphQLClient(
        cache: GraphQLCache(),
        link: SuwayomiAuthLink(
          authType: () => AuthType.basic,
          getHeaders: () async => null,
          refreshAccessToken: () async =>
              throw StateError('Basic cannot refresh'),
          onNeedsReauth: () => recoveryRequested = true,
        ).concat(raw.link),
      );
      final result = await client.query$ServerSignInStatus(
        Options$Query$ServerSignInStatus(fetchPolicy: FetchPolicy.noCache),
      );
      expect(result.exception, isNotNull);
      expect(isSignInSessionEnded(result.exception!), response.$1 != 500);
      expect(recoveryRequested, response.$1 != 500);
    });
  }
}
