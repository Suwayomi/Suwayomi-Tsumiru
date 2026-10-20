import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/custom_headers_store.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

class _RealHttpOverrides extends HttpOverrides {}

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
}
