// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Web sign-in against a Simple-login server: the `login` mutation succeeds
// but the fresh token authorises nothing, so it must never be saved.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/ui_login_token_rejected.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/utils/platform/web_auth_mode.dart';

class _RealHttpOverrides extends HttpOverrides {}

String _testToken() {
  final payload = jsonEncode({
    'exp':
        DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
        1000,
  });
  return 'e30.${base64Url.encode(utf8.encode(payload)).replaceAll('=', '')}.test-signature';
}

class _UiLoginChain extends Link {
  final operations = <String>[];
  final token = _testToken();

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final operation = request.operation.document.definitions
        .whereType<OperationDefinitionNode>()
        .single
        .name!
        .value;
    operations.add(operation);
    final user = {
      '__typename': 'UserType',
      'id': 2,
      'username': 'Reader',
      'roles': ['USER'],
      'permissions': <String>[],
    };
    final payload = switch (operation) {
      'Login' => {
        'login': {
          '__typename': 'LoginPayload',
          'accessToken': token,
          'refreshToken': 'test-refresh',
        },
      },
      'AccountCapability' || 'CurrentAccount' => {'user': user},
      'OfflineServerIdentity' => {
        'metas': {
          '__typename': 'MetaTypeConnection',
          'nodes': [
            {
              '__typename': 'GlobalMetaType',
              'key': 'tsumiru_server_instance_id',
              'value': 'web-test-catalog',
            },
          ],
        },
      },
      _ => throw StateError('Unexpected test operation: $operation'),
    };
    yield Response(
      response: {},
      data: {
        '__typename': operation == 'Login' ? 'Mutation' : 'Query',
        ...payload,
      },
    );
  }
}

Future<HttpServer> _probeServer({
  required bool authorized,
  required List<String?> seenAuth,
  List<Map<String, String>>? seenHeaders,
  int statusCode = 200,
  String? rawBody,
  Duration delay = Duration.zero,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      seenAuth.add(request.headers.value(HttpHeaders.authorizationHeader));
      if (seenHeaders != null) {
        final map = <String, String>{};
        request.headers.forEach((name, values) => map[name] = values.join(','));
        seenHeaders.add(map);
      }
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        rawBody ??
            (authorized
                ? jsonEncode({
                    'data': {
                      'downloadStatus': {'__typename': 'DownloadStatus'},
                    },
                  })
                : jsonEncode({
                    'data': null,
                    'errors': [
                      {'message': 'Unauthorized'},
                    ],
                  })),
      );
      await request.response.close();
    } catch (_) {}
  });
  return server;
}

Future<ProviderContainer> _container(String base, {required bool isWeb}) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({
    DBKeys.serverUrl.name: base,
    DBKeys.serverExternalUrl.name: base,
    DBKeys.serverPortToggle.name: false,
  });
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
      isWebProvider.overrideWithValue(isWeb),
    ],
  );
  await container.read(authCredentialsStoreProvider.future);
  return container;
}

Future<void> _runZoned(Future<void> Function() body) => HttpOverrides.runZoned(
  body,
  createHttpClient: _RealHttpOverrides().createHttpClient,
);

void main() {
  test('a UI token the server rejects is not saved on web', () async {
    final seenAuth = <String?>[];
    final probe = await _probeServer(authorized: false, seenAuth: seenAuth);
    addTearDown(() => probe.close(force: true));
    final base = 'http://127.0.0.1:${probe.port}';
    await _runZoned(() async {
      final container = await _container(base, isWeb: true);
      addTearDown(container.dispose);
      final link = _UiLoginChain();
      final client = GraphQLClient(link: link, cache: GraphQLCache());
      await expectLater(
        container
            .read(authCoordinatorProvider.notifier)
            .loginUi(
              gqlClient: client,
              username: 'reader',
              password: 'password',
              serverBaseUrl: base,
            ),
        throwsA(isA<UiLoginTokenRejected>()),
      );
      expect(link.operations, ['Login']);
      expect(seenAuth, ['Bearer ${link.token}']);
      final credentials = container
          .read(authCredentialsStoreProvider)
          .requireValue;
      expect(credentials.uiAccessToken, isNull);
      expect(credentials.accountBinding, isNull);
    });
  });

  test('a proxy failure after sign-in does not block web sign-in', () async {
    final seenAuth = <String?>[];
    final probe = await _probeServer(
      authorized: false,
      seenAuth: seenAuth,
      statusCode: 502,
      rawBody: '<html>Bad Gateway</html>',
    );
    addTearDown(() => probe.close(force: true));
    final base = 'http://127.0.0.1:${probe.port}';
    await _runZoned(() async {
      final container = await _container(base, isWeb: true);
      addTearDown(container.dispose);
      final link = _UiLoginChain();
      final client = GraphQLClient(link: link, cache: GraphQLCache());
      await container
          .read(authCoordinatorProvider.notifier)
          .loginUi(
            gqlClient: client,
            username: 'reader',
            password: 'password',
            serverBaseUrl: base,
          );
      expect(
        container.read(authCredentialsStoreProvider).requireValue.uiAccessToken,
        link.token,
      );
    });
  });
}
