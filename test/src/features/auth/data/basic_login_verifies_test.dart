// Copyright (c) 2026 Contributors to the Suwayomi project

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/basic_credentials_rejected.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

class _RealHttpOverrides extends HttpOverrides {}

/// A server that only accepts one Basic credential, like basic_auth does.
Future<HttpServer> _basicAuthServer(String expected) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header != 'Basic $expected') {
      request.response.statusCode = 401;
      request.response.headers.set('WWW-Authenticate', 'Basic');
      await request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'data': {
          'downloadStatus': {'__typename': 'DownloadStatus'},
        },
      }),
    );
    await request.response.close();
  });
  return server;
}

Future<ProviderContainer> _containerFor(HttpServer server) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({
    DBKeys.serverUrl.name: 'http://127.0.0.1:${server.port}',
    DBKeys.serverExternalUrl.name: 'http://127.0.0.1:${server.port}',
    DBKeys.serverPortToggle.name: false,
  });
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
    ],
  );
  await container.read(authCredentialsStoreProvider.future);
  await container.read(credentialsProvider.future);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final good = base64.encode(utf8.encode('admin:adminwords'));

  test('a rejected Basic password is not stored as a sign-in', () async {
    final server = await _basicAuthServer(good);
    addTearDown(() => server.close(force: true));
    await HttpOverrides.runZoned(() async {
      final container = await _containerFor(server);
      addTearDown(container.dispose);
      await expectLater(
        container
            .read(authCoordinatorProvider.notifier)
            .loginBasic(
              serverBaseUrl: 'http://127.0.0.1:${server.port}',
              username: 'admin',
              // One key off, exactly the typo that reported a successful sign-in
              // and then 401'd every request.
              password: 'adminqords',
            ),
        throwsA(isA<BasicCredentialsRejected>()),
      );
      expect(container.read(credentialsProvider).value, isNull);
    }, createHttpClient: _RealHttpOverrides().createHttpClient);
  });

  test('the right Basic password is stored', () async {
    final server = await _basicAuthServer(good);
    addTearDown(() => server.close(force: true));
    await HttpOverrides.runZoned(() async {
      final container = await _containerFor(server);
      addTearDown(container.dispose);
      await container
          .read(authCoordinatorProvider.notifier)
          .loginBasic(
            serverBaseUrl: 'http://127.0.0.1:${server.port}',
            username: 'admin',
            password: 'adminwords',
          );
      expect(container.read(credentialsProvider).value, 'Basic $good');
    }, createHttpClient: _RealHttpOverrides().createHttpClient);
  });
}
