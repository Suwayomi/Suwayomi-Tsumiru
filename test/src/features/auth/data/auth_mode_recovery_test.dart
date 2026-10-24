import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/auth_recovery_target.dart';
import 'package:tsumiru/src/features/auth/data/auth_state.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

class _StatusLink extends Link {
  _StatusLink(this.mode);
  String mode;
  String audience = 'server';
  bool refused = false;
  final headers = <Map<String, String>>[];

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    headers.add(request.context.entry<HttpLinkHeaders>()?.headers ?? {});
    if (refused) {
      yield Response(
        response: {},
        errors: const [GraphQLError(message: 'Unauthorized')],
      );
    } else {
      yield Response(
        response: {},
        data: {
          '__typename': 'Query',
          'settings': {
            '__typename': 'SettingsType',
            'authMode': mode,
            'jwtAudience': audience,
          },
        },
      );
    }
  }
}

Future<ProviderContainer> _setup(AuthType mode, _StatusLink link) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({DBKeys.authType.name: mode.name});
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
      unauthenticatedGraphQlClientProvider.overrideWithValue(
        GraphQLClient(link: link, cache: GraphQLCache()),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(authCredentialsStoreProvider.future);
  await container.read(credentialsProvider.future);
  container.read(authTypeKeyProvider.notifier).update(mode);
  container.read(authCredentialsStoreProvider.notifier).activateSession();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final change in [
    (old: AuthType.none, server: 'UI_LOGIN', target: AuthType.uiLogin),
    (old: AuthType.uiLogin, server: 'BASIC_AUTH', target: AuthType.basic),
    (old: AuthType.basic, server: 'SIMPLE_LOGIN', target: AuthType.simpleLogin),
    (old: AuthType.simpleLogin, server: 'UI_LOGIN', target: AuthType.uiLogin),
  ]) {
    test(
      'resume discovers external ${change.old} → ${change.target} without committing mode',
      () async {
        final link = _StatusLink(change.server);
        final container = await _setup(change.old, link);
        await container.read(authModeReconcilerProvider).reconcile();
        expect(container.read(authRecoveryTargetProvider), change.target);
        expect(container.read(needsReauthProvider), isTrue);
        expect(container.read(authTypeKeyProvider), change.old);
      },
    );
  }
  for (final mode in [AuthType.basic, AuthType.simpleLogin, AuthType.uiLogin]) {
    test(
      'external credential or audience rejection preserves $mode recovery when discovery is refused',
      () async {
        final link = _StatusLink('UI_LOGIN')..refused = true;
        final container = await _setup(mode, link);
        await container
            .read(authModeReconcilerProvider)
            .reconcile(authFailure: true);
        expect(container.read(authRecoveryTargetProvider), mode);
        expect(container.read(needsReauthProvider), isTrue);
        expect(container.read(authTypeKeyProvider), mode);
      },
    );
  }
  test(
    'known external audience change drops tokens and replaces clients',
    () async {
      final link = _StatusLink('UI_LOGIN');
      final container = await _setup(AuthType.uiLogin, link);
      final store = container.read(authCredentialsStoreProvider.notifier);
      await store.saveUiLoginTokens(
        accessToken: 'old-token',
        refreshToken: 'old-refresh',
      );
      store.activateSession();
      final reconciler = container.read(authModeReconcilerProvider);
      await reconciler.reconcile();
      final before = store.sessionEpoch;
      link.audience = 'new audience';
      await reconciler.reconcile();
      expect(store.uiLoginTokens(), isNull);
      expect(store.sessionEpoch, greaterThan(before));
      expect(container.read(authRecoveryTargetProvider), AuthType.uiLogin);
      expect(container.read(needsReauthProvider), isTrue);
    },
  );
  test(
    'external UI login → None clears all old credentials and account binding',
    () async {
      final container = await _setup(AuthType.uiLogin, _StatusLink('NONE'));
      final store = container.read(authCredentialsStoreProvider.notifier);
      await store.saveUiLoginTokens(
        accessToken: 'old',
        refreshToken: 'old-refresh',
      );
      store.activateSession();
      await container.read(authModeReconcilerProvider).reconcile();
      expect(container.read(authTypeKeyProvider), AuthType.none);
      expect(store.uiLoginTokens(), isNull);
      expect(
        container.read(authCredentialsStoreProvider).value?.accountBinding,
        isNull,
      );
      expect(container.read(authRecoveryTargetProvider), isNull);
    },
  );
}
