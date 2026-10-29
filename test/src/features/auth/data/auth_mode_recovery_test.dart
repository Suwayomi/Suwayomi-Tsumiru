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
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/auth_recovery_target.dart';
import 'package:tsumiru/src/features/auth/data/auth_state.dart';
import 'package:tsumiru/src/features/onboarding/data/onboarding_complete.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/utils/network/graphql_errors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('masked NONE recovery preserves the current credentials', () async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      DBKeys.authType.name: AuthType.uiLogin.index,
      DBKeys.onboardingComplete.name: true,
    });
    final client = GraphQLClient(
      cache: GraphQLCache(),
      link: HttpLink(
        'http://localhost/graphql',
        httpClient: MockClient(
          (_) async => http.Response(
            '{"data":{"__typename":"Query","settings":{"__typename":"SettingsType","authMode":"NONE","jwtAudience":"server"}}}',
            200,
          ),
        ),
        httpResponseDecoder: tsumiruHttpResponseDecoder,
      ),
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
              permissions: const [],
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authCredentialsStoreProvider.future);
    await container.read(credentialsProvider.future);
    final store = container.read(authCredentialsStoreProvider.notifier);
    await store.saveUiLoginTokens(accessToken: 'old', refreshToken: 'refresh');
    store.activateSession();
    final epoch = store.sessionEpoch;
    await container.read(authModeReconcilerProvider).reconcile();
    expect(container.read(authRecoveryTargetProvider), isNull);
    await container
        .read(authModeReconcilerProvider)
        .reconcile(authFailure: true);
    expect(container.read(authRecoveryTargetProvider), AuthType.uiLogin);
    expect(container.read(needsReauthProvider), isTrue);
    expect(container.read(authTypeKeyProvider), AuthType.uiLogin);
    expect(store.uiLoginTokens()?.accessToken, 'old');
    expect(store.sessionEpoch, epoch);
    container.read(authRecoveryTargetProvider.notifier).set(AuthType.uiLogin);
    await container
        .read(authModeReconcilerProvider)
        .reconcile(authFailure: true);
    expect(container.read(authRecoveryTargetProvider), AuthType.uiLogin);
  });

  test('auth failure before setup finishes stays silent', () async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      DBKeys.authType.name: AuthType.uiLogin.index,
    });
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(onboardingCompleteProvider), isFalse);
    await container
        .read(authModeReconcilerProvider)
        .reconcile(authFailure: true);
    expect(container.read(needsReauthProvider), isFalse);
    expect(container.read(authRecoveryTargetProvider), isNull);
  });
}
