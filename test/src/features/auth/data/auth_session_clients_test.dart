import 'dart:async';
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
import 'package:tsumiru/src/features/auth/data/custom_headers_store.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

class _RealHttpOverrides extends HttpOverrides {}

class _DelayedCredentials extends AuthCredentialsStore {
  _DelayedCredentials(this.ready);
  final Completer<AuthCredentialsState> ready;
  @override
  Future<AuthCredentialsState> build() => ready.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('late LAN probe cannot redirect a replacement server login', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final started = Completer<void>();
    final release = Completer<void>();
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await server.close(force: true);
    });
    server.listen((request) async {
      if (!started.isCompleted) started.complete();
      await release.future;
      request.response.statusCode = 401;
      await request.response.close();
    });
    await HttpOverrides.runZoned(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        DBKeys.serverUrl.name: 'https://a.example',
        DBKeys.serverExternalUrl.name: 'https://a.example',
        DBKeys.serverLanUrl.name: 'http://127.0.0.1:${server.port}',
        DBKeys.serverPortToggle.name: false,
      });
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authCredentialsStoreProvider.future);
      await container.read(credentialsProvider.future);
      final resolver = container.read(serverEndpointResolverProvider.notifier);
      final pending = resolver.refresh();
      await started.future;
      container.read(serverLanUrlProvider.notifier).update(null);
      await container
          .read(serverExternalUrlProvider.notifier)
          .update('https://b.example');
      await container
          .read(authCredentialsStoreProvider.notifier)
          .saveUiLoginTokens(accessToken: 'B', refreshToken: 'R-B');
      release.complete();
      await pending;
      expect(container.read(serverUrlProvider), 'https://b.example');
      expect(
        container.read(authCredentialsStoreProvider).requireValue.uiAccessToken,
        'B',
      );
    }, createHttpClient: _RealHttpOverrides().createHttpClient);
  });

  test('account changes replace HTTP and subscription clients', () async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await container.read(authCredentialsStoreProvider.future);
    await container.read(credentialsProvider.future);
    await container.read(customHttpHeadersProvider.future);
    final store = container.read(authCredentialsStoreProvider.notifier);
    final http = container.read(graphQlClientProvider);
    final socket = container.read(graphQlSubscriptionClientProvider);
    await store.withIdentityChange(() async {
      await store.saveUiLoginTokens(accessToken: 'A', refreshToken: 'R');
    });
    final nextHttp = container.read(graphQlClientProvider);
    final nextSocket = container.read(graphQlSubscriptionClientProvider);
    expect(nextHttp, isNot(same(http)));
    expect(nextSocket, isNot(same(socket)));
    await store.updateUiLoginAccessToken('A2');
    expect(container.read(graphQlClientProvider), same(nextHttp));
    expect(container.read(graphQlSubscriptionClientProvider), same(nextSocket));
  });
  test(
    'same-server account switch fences retained clients and late responses',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final receivedA = Completer<void>();
      final releaseA = Completer<void>();
      final authorizations = <String?>[];
      addTearDown(() async {
        if (!releaseA.isCompleted) releaseA.complete();
        await server.close(force: true);
      });
      server.listen((request) async {
        final authorization = request.headers.value('authorization');
        authorizations.add(authorization);
        await request.drain<void>();
        if (authorization == 'Bearer A') {
          receivedA.complete();
          await releaseA.future;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': {'account': authorization},
          }),
        );
        await request.response.close();
      });
      await HttpOverrides.runZoned(() async {
        FlutterSecureStorage.setMockInitialValues({
          'auth.ui.accessToken': 'A',
          'auth.ui.refreshToken': 'refresh-A',
        });
        SharedPreferences.setMockInitialValues({
          DBKeys.serverUrl.name: 'http://127.0.0.1',
          DBKeys.serverPort.name: server.port,
          DBKeys.serverPortToggle.name: true,
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
        await container.read(authCredentialsStoreProvider.future);
        await container.read(credentialsProvider.future);
        await container.read(customHttpHeadersProvider.future);
        final oldClient = container.read(graphQlClientProvider);
        final pendingA = oldClient.query(
          QueryOptions(
            document: gql('query PendingA { account }'),
            fetchPolicy: FetchPolicy.noCache,
          ),
        );
        await receivedA.future;
        final store = container.read(authCredentialsStoreProvider.notifier);
        await store.saveUiLoginTokens(
          accessToken: 'B',
          refreshToken: 'refresh-B',
        );

        final retainedResult = await oldClient.query(
          QueryOptions(
            document: gql('query RetainedA { account }'),
            fetchPolicy: FetchPolicy.noCache,
          ),
        );
        expect(retainedResult.hasException, isTrue);
        expect(retainedResult.data, isNull);
        expect(authorizations, ['Bearer A']);

        final newClient = container.read(graphQlClientProvider);
        expect(newClient, isNot(same(oldClient)));
        final resultB = await newClient.query(
          QueryOptions(
            document: gql('query CurrentB { account }'),
            fetchPolicy: FetchPolicy.noCache,
          ),
        );
        expect(resultB.hasException, isFalse);
        expect(resultB.data, {'account': 'Bearer B'});

        releaseA.complete();
        final resultA = await pendingA;
        expect(resultA.hasException, isTrue);
        expect(resultA.data, isNull);
        expect(authorizations, ['Bearer A', 'Bearer B']);
      }, createHttpClient: _RealHttpOverrides().createHttpClient);
    },
  );

  test(
    'login uses a separate client without the previous account token',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      String? authorization;
      server.listen((request) async {
        authorization = request.headers.value('authorization');
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': {'ok': true},
          }),
        );
        await request.response.close();
      });
      await HttpOverrides.runZoned(() async {
        FlutterSecureStorage.setMockInitialValues({
          'auth.ui.accessToken': 'previous-account',
          'auth.ui.refreshToken': 'previous-refresh',
        });
        SharedPreferences.setMockInitialValues({
          DBKeys.serverUrl.name: 'http://127.0.0.1',
          DBKeys.serverPort.name: server.port,
          DBKeys.serverPortToggle.name: true,
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
        await container.read(authCredentialsStoreProvider.future);
        await container.read(credentialsProvider.future);
        await container.read(customHttpHeadersProvider.future);
        final result = await container
            .read(unauthenticatedGraphQlClientProvider)
            .query(
              QueryOptions(
                document: gql('query { ok }'),
                fetchPolicy: FetchPolicy.noCache,
              ),
            );
        expect(result.exception, isNull);
        expect(result.data, {'ok': true});
        expect(authorization, isNull);
      }, createHttpClient: _RealHttpOverrides().createHttpClient);
    },
  );
  test(
    'read failover preserves the account and delivers the fallback response',
    () async {
      final failed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final failedUrl = 'http://127.0.0.1:${failed.port}';
      await failed.close(force: true);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final headers = <String?>[];
      server.listen((request) async {
        headers.add(request.headers.value('authorization'));
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': {'account': 'A'},
          }),
        );
        await request.response.close();
      });
      await HttpOverrides.runZoned(() async {
        FlutterSecureStorage.setMockInitialValues({
          'auth.ui.accessToken': 'A',
          'auth.ui.refreshToken': 'refresh-A',
        });
        SharedPreferences.setMockInitialValues({
          DBKeys.serverUrl.name: failedUrl,
          DBKeys.serverExternalUrl.name: 'http://127.0.0.1:${server.port}',
          DBKeys.serverPortToggle.name: false,
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
        await container.read(authCredentialsStoreProvider.future);
        await container.read(credentialsProvider.future);
        await container.read(customHttpHeadersProvider.future);
        container.listen(graphQlClientProvider, (_, _) {});
        final result = await container
            .read(graphQlClientProvider)
            .query(
              QueryOptions(
                document: gql('query Failover { account }'),
                fetchPolicy: FetchPolicy.noCache,
              ),
            );
        expect(result.exception, isNull);
        expect(result.data, {'account': 'A'});
        expect(headers, ['Bearer A']);
      }, createHttpClient: _RealHttpOverrides().createHttpClient);
    },
  );

  test(
    'credential hydration preserves clients and their waiting requests',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final authorization = request.headers.value('authorization');
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': {'account': authorization},
          }),
        );
        await request.response.close();
      });
      await HttpOverrides.runZoned(() async {
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({
          DBKeys.serverUrl.name: 'http://127.0.0.1:${server.port}',
          DBKeys.serverPortToggle.name: false,
          DBKeys.authType.name: AuthType.uiLogin.index,
        });
        final ready = Completer<AuthCredentialsState>();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
            authCredentialsStoreProvider.overrideWith(
              () => _DelayedCredentials(ready),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(credentialsProvider.future);
        await container.read(customHttpHeadersProvider.future);
        final client = container.read(graphQlClientProvider);
        final socket = container.read(graphQlSubscriptionClientProvider);
        final pending = client.query(
          QueryOptions(
            document: gql('query Hydrated { account }'),
            fetchPolicy: FetchPolicy.noCache,
          ),
        );
        ready.complete(
          const AuthCredentialsState(
            uiAccessToken: 'A',
            uiRefreshToken: 'refresh-A',
          ),
        );
        final result = await pending;
        expect(result.exception, isNull);
        expect(result.data, {'account': 'Bearer A'});
        expect(container.read(graphQlClientProvider), same(client));
        expect(container.read(graphQlSubscriptionClientProvider), same(socket));
      }, createHttpClient: _RealHttpOverrides().createHttpClient);
    },
  );
}
