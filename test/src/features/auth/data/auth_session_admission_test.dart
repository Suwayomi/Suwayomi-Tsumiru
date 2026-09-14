import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/auth_state.dart';
import 'package:tsumiru/src/features/auth/data/custom_headers_store.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late ProviderContainer container;
  late AuthCredentialsStore store;

  Future<ProviderContainer> createContainer() async {
    final result = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(result.dispose);
    await result.read(authCredentialsStoreProvider.future);
    return result;
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({
      'auth.ui.accessToken': 'A',
      'auth.ui.refreshToken': 'refresh-A',
    });
    SharedPreferences.setMockInitialValues({
      DBKeys.authType.name: AuthType.uiLogin.index,
    });
    preferences = await SharedPreferences.getInstance();
    container = await createContainer();
    store = container.read(authCredentialsStoreProvider.notifier);
    store.activateSession();
  });

  test(
    'unauthorized response while signed out does not report expiry',
    () async {
      await store.clearUiLoginTokens();
      store.activateSession();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': null,
            'errors': [
              {'message': 'Unauthorized'},
            ],
          }),
        );
        await request.response.close();
      });
      await preferences.setString(DBKeys.serverUrl.name, 'http://127.0.0.1');
      await preferences.setInt(DBKeys.serverPort.name, server.port);
      await preferences.setBool(DBKeys.serverPortToggle.name, true);
      await HttpOverrides.runZoned(
        () async {
          await container.read(credentialsProvider.future);
          await container.read(customHttpHeadersProvider.future);
          final result = await container
              .read(graphQlClientProvider)
              .query(
                QueryOptions(
                  document: gql('query SignedOut { user { id } }'),
                  fetchPolicy: FetchPolicy.networkOnly,
                ),
              );
          expect(result.hasException, isTrue);
          expect(container.read(needsReauthProvider), isFalse);
        },
        createHttpClient: (context) =>
            _RealHttpOverrides().createHttpClient(context),
      );
    },
  );

  test(
    'committing B closes both old and newly captured work in activated A root',
    () async {
      final capturedA = store.captureSession();
      expect(capturedA(), isTrue);
      await store.saveUiLoginTokens(
        accessToken: 'B',
        refreshToken: 'refresh-B',
      );
      expect(store.sessionChanging, isFalse);
      expect(store.sessionAdmitted, isFalse);
      expect(capturedA(), isFalse);
      expect(store.captureSession()(), isFalse);

      final next = await createContainer();
      final nextStore = next.read(authCredentialsStoreProvider.notifier);
      nextStore.activateSession();
      expect(
        next.read(authCredentialsStoreProvider).requireValue.uiAccessToken,
        'B',
      );
      expect(nextStore.sessionAdmitted, isTrue);
      expect(nextStore.captureSession()(), isTrue);
      expect(store.captureSession()(), isFalse);
    },
  );

  test(
    'same-account token refresh preserves active admission and captured work',
    () async {
      final current = store.captureSession();
      final epoch = store.sessionEpoch;
      await store.updateUiLoginAccessToken(
        'A-refreshed',
        forEpoch: store.serverEpoch,
      );
      expect(store.sessionEpoch, epoch);
      expect(store.sessionAdmitted, isTrue);
      expect(current(), isTrue);
      expect(store.captureSession()(), isTrue);
      expect(
        container.read(authCredentialsStoreProvider).requireValue.uiAccessToken,
        'A-refreshed',
      );
    },
  );

  test(
    'refused transition can reactivate A without reviving old captured work',
    () async {
      final oldWork = store.captureSession();
      await expectLater(
        store.withIdentityChange<void>(() async {
          throw StateError('Download drain refused');
        }),
        throwsStateError,
      );
      expect(store.sessionAdmitted, isFalse);
      expect(oldWork(), isFalse);
      expect(store.captureSession()(), isFalse);
      expect(
        container.read(authCredentialsStoreProvider).requireValue.uiAccessToken,
        'A',
      );
      store.activateSession();
      expect(store.sessionAdmitted, isTrue);
      expect(store.captureSession()(), isTrue);
      expect(oldWork(), isFalse);
    },
  );

  test(
    'rebuilt old-root GraphQL client cannot send committed B credentials',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final authorizations = <String?>[];
      server.listen((request) async {
        final authorization = request.headers.value('authorization');
        authorizations.add(authorization);
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': {'account': authorization},
          }),
        );
        await request.response.close();
      });
      await preferences.setString(DBKeys.serverUrl.name, 'http://127.0.0.1');
      await preferences.setInt(DBKeys.serverPort.name, server.port);
      await preferences.setBool(DBKeys.serverPortToggle.name, true);
      await HttpOverrides.runZoned(() async {
        await container.read(credentialsProvider.future);
        await container.read(customHttpHeadersProvider.future);
        final initial = container.read(graphQlClientProvider);
        final first = await initial.query(
          QueryOptions(
            document: gql('query A { account }'),
            fetchPolicy: FetchPolicy.noCache,
          ),
        );
        expect(first.hasException, isFalse);
        expect(authorizations, ['Bearer A']);
        await store.saveUiLoginTokens(
          accessToken: 'B',
          refreshToken: 'refresh-B',
        );
        final rebuilt = container.read(graphQlClientProvider);
        expect(rebuilt, isNot(same(initial)));
        final denied = await rebuilt.query(
          QueryOptions(
            document: gql('query DeniedB { account }'),
            fetchPolicy: FetchPolicy.noCache,
          ),
        );
        expect(denied.hasException, isTrue);
        expect(denied.data, isNull);
        expect(authorizations, ['Bearer A']);

        final next = await createContainer();
        next.read(authCredentialsStoreProvider.notifier).activateSession();
        await next.read(credentialsProvider.future);
        await next.read(customHttpHeadersProvider.future);
        final admitted = await next
            .read(graphQlClientProvider)
            .query(
              QueryOptions(
                document: gql('query B { account }'),
                fetchPolicy: FetchPolicy.noCache,
              ),
            );
        expect(admitted.hasException, isFalse);
        expect(admitted.data, {'account': 'Bearer B'});
        expect(authorizations, ['Bearer A', 'Bearer B']);
      }, createHttpClient: _RealHttpOverrides().createHttpClient);
    },
  );
}
