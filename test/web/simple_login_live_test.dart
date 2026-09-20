@TestOn('browser')
library;

import 'dart:ui' as ui;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/custom_headers_store.dart';
import 'package:tsumiru/src/features/auth/data/simple_login_client.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache.dart';

const server = String.fromEnvironment('SIMPLE_LOGIN_TEST_URL');
const username = String.fromEnvironment('SIMPLE_LOGIN_TEST_USER');
const password = String.fromEnvironment('SIMPLE_LOGIN_TEST_PASSWORD');
const coverPath = String.fromEnvironment(
  'SIMPLE_LOGIN_TEST_COVER_PATH',
  defaultValue: '/api/v1/manga/1/thumbnail',
);
const externalImage = String.fromEnvironment(
  'SIMPLE_LOGIN_TEST_EXTERNAL_IMAGE',
);
const crossSiteServer = String.fromEnvironment(
  'SIMPLE_LOGIN_TEST_CROSS_SITE_URL',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('browser session authorizes GraphQL and protected covers', () async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      DBKeys.serverUrl.name: server,
      DBKeys.serverExternalUrl.name: server,
      DBKeys.serverPortToggle.name: false,
      DBKeys.authType.name: AuthType.simpleLogin.index,
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
    await container
        .read(authCoordinatorProvider.notifier)
        .loginSimple(
          serverBaseUrl: server,
          username: username,
          password: password,
        );
    expect(
      container
          .read(authCredentialsStoreProvider)
          .requireValue
          .simpleLoginCookie,
      kBrowserManagedSimpleSession,
    );
    final result = await container
        .read(graphQlClientProvider)
        .query(
          QueryOptions(
            document: gql('query { downloadStatus { __typename } }'),
            fetchPolicy: FetchPolicy.noCache,
          ),
        );
    expect(result.hasException, isFalse, reason: '${result.exception}');
    expect(result.data?['downloadStatus']['__typename'], 'DownloadStatus');
    final cover = await container
        .read(coverCacheManagerProvider)
        .getSingleFile('$server$coverPath');
    final bytes = await cover.readAsBytes();
    expect(bytes.length, greaterThan(100));
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, greaterThan(1));
    expect(frame.image.height, greaterThan(1));
    if (externalImage.isNotEmpty) {
      final external = await container
          .read(coverCacheManagerProvider)
          .getSingleFile(externalImage);
      expect(await external.readAsBytes(), isNotEmpty);
      final client = http.Client();
      try {
        expect((await client.get(Uri.parse(externalImage))).statusCode, 200);
      } finally {
        client.close();
      }
    }
    final store = container.read(authCredentialsStoreProvider.notifier);
    await store.clearSimpleLoginCookie();
    await store.clearPassword();
    await expectLater(
      container
          .read(authCoordinatorProvider.notifier)
          .loginSimple(
            serverBaseUrl: server,
            username: username,
            password: '$password-wrong',
          ),
      throwsA(isA<SimpleLoginAuthFailure>()),
    );
    expect(
      container
          .read(authCredentialsStoreProvider)
          .requireValue
          .simpleLoginCookie,
      isNull,
    );
    expect(
      container.read(authCredentialsStoreProvider).requireValue.password,
      isNull,
    );
    if (crossSiteServer.isNotEmpty) {
      await expectLater(
        container
            .read(authCoordinatorProvider.notifier)
            .loginSimple(
              serverBaseUrl: crossSiteServer,
              username: username,
              password: password,
            ),
        throwsA(isA<SimpleLoginSessionFailure>()),
      );
      expect(
        container
            .read(authCredentialsStoreProvider)
            .requireValue
            .simpleLoginCookie,
        isNull,
      );
      expect(
        container.read(authCredentialsStoreProvider).requireValue.password,
        isNull,
      );
    }
    frame.image.dispose();
    codec.dispose();
  }, skip: server.isEmpty);
}
