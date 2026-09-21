// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/custom_headers_store.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

String _buildJwt(Map<String, dynamic> payload) {
  String b64Url(String s) =>
      base64Url.encode(utf8.encode(s)).replaceAll('=', '');
  return '${b64Url('{"alg":"HS256"}')}.${b64Url(jsonEncode(payload))}.sig';
}

class _InMemorySecureStorage implements FlutterSecureStorage {
  _InMemorySecureStorage(Map<String, String> seed) : _store = {...seed};
  final Map<String, String> _store;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _FakeClientSource {
  int port = 1;
  final built = <int>[];
}

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a fired proactive refresh reads the CURRENT unauthenticatedGraphQlClientProvider, '
    'not the one captured when it was scheduled',
    () async {
      debugResetAuthCoordinatorSingleFlight();

      final expiredJwt = _buildJwt({
        'exp':
            DateTime.now()
                .toUtc()
                .subtract(const Duration(minutes: 5))
                .millisecondsSinceEpoch ~/
            1000,
      });
      final storage = _InMemorySecureStorage({
        'auth.ui.accessToken': expiredJwt,
        'auth.ui.refreshToken': 'R',
      });

      final source = _FakeClientSource();
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          unauthenticatedGraphQlClientProvider.overrideWith((ref) {
            source.built.add(source.port);
            return GraphQLClient(
              link: HttpLink('http://127.0.0.1:${source.port}'),
              cache: GraphQLCache(),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authCredentialsStoreProvider.future);

      container.read(authCoordinatorProvider.notifier);

      source.port = 2;
      container.invalidate(unauthenticatedGraphQlClientProvider);

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        source.built.contains(2),
        isTrue,
        reason:
            'the fired refresh must have read unauthenticatedGraphQlClientProvider '
            'again to pick up port 2 — before the fix it kept using '
            'whatever client was live when the Timer was first scheduled '
            '(port 1, or no read at all), forever.',
      );
      expect(
        source.built.last,
        2,
        reason:
            'the LAST client built must be the current one at fire '
            'time, not a stale one from scheduling time',
      );
    },
  );
  test('expired proactive refresh sends no account authorization', () async {
    debugResetAuthCoordinatorSingleFlight();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final authorizations = <String?>[];
    final refreshed = Completer<void>();
    final freshJwt = _buildJwt({
      'exp':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000,
    });
    server.listen((request) async {
      final authorization = request.headers.value('authorization');
      authorizations.add(authorization);
      final body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      expect(body['query'], contains('refreshToken'));
      request.response.headers.contentType = ContentType.json;
      if (authorization != null) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write(
          jsonEncode({
            'errors': [
              {'message': 'Expired access token'},
            ],
          }),
        );
      } else {
        request.response.write(
          jsonEncode({
            'data': {
              '__typename': 'Mutation',
              'refreshToken': {
                '__typename': 'RefreshTokenPayload',
                'accessToken': freshJwt,
              },
            },
          }),
        );
      }
      await request.response.close();
    });
    await HttpOverrides.runZoned(() async {
      FlutterSecureStorage.setMockInitialValues({
        'auth.ui.accessToken': _buildJwt({
          'exp':
              DateTime.now()
                  .subtract(const Duration(minutes: 5))
                  .millisecondsSinceEpoch ~/
              1000,
        }),
        'auth.ui.refreshToken': 'refresh-a',
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
      addTearDown(() {
        container.dispose();
        debugResetAuthCoordinatorSingleFlight();
      });
      await container.read(authCredentialsStoreProvider.future);
      await container.read(credentialsProvider.future);
      await container.read(customHttpHeadersProvider.future);
      container.listen(authCredentialsStoreProvider, (_, next) {
        if (next.value?.uiAccessToken == freshJwt && !refreshed.isCompleted) {
          refreshed.complete();
        }
      });
      container.read(authCoordinatorProvider.notifier);
      await refreshed.future.timeout(const Duration(seconds: 3));
      expect(authorizations, [null]);
      expect(
        container.read(authCredentialsStoreProvider).value?.uiAccessToken,
        freshJwt,
      );
      expect(
        await container
            .read(secureStorageProvider)
            .read(key: 'auth.ui.accessToken'),
        freshJwt,
      );
    }, createHttpClient: _RealHttpOverrides().createHttpClient);
  });
}
