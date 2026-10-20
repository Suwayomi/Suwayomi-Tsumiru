// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/utils/crash/diagnostics.dart';

String _jwt(Duration expIn) {
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp = DateTime.now().toUtc().add(expIn).millisecondsSinceEpoch ~/ 1000;
  return '${part({'alg': 'HS256'})}.${part({'exp': exp})}.sig';
}

Response _success(String accessToken) => Response(
  data: {
    '__typename': 'Mutation',
    'refreshToken': {
      '__typename': 'RefreshTokenPayload',
      'accessToken': accessToken,
    },
  },
  response: const {},
);

/// What one refresh call answers: a [Response], or an error it throws.
typedef _Answer = Object;

final _unreachable = ServerException(
  originalException: const SocketException('HTTP connection timed out'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  final fresh = _jwt(const Duration(minutes: 5));
  final lines = <String>[];

  setUp(() async {
    debugResetAuthCoordinatorSingleFlight();
    SharedPreferences.setMockInitialValues({
      DBKeys.authType.name: AuthType.uiLogin.index,
    });
    prefs = await SharedPreferences.getInstance();
    lines.clear();
    setDiagnosticSink(lines.add);
  });

  tearDown(() {
    setDiagnosticSink(null);
    debugResetAuthCoordinatorSingleFlight();
  });

  /// Runs [body] with a store holding [access], under fake time so the
  /// coordinator's proactive timer never fires on its own. Refresh calls
  /// (from the gate or the handover retry) answer from [answers] in order.
  void withStore(
    String access,
    List<_Answer> answers,
    void Function(
      FakeAsync async,
      ProviderContainer container,
      List<Object> calls,
      GraphQLClient client,
    )
    body,
  ) {
    fakeAsync((async) {
      FlutterSecureStorage.setMockInitialValues({
        'auth.ui.accessToken': access,
        'auth.ui.refreshToken': 'refresh',
      });
      final calls = <Object>[];
      final client = GraphQLClient(
        link: Link.function((request, [forward]) {
          final answer = answers[calls.length];
          calls.add(answer);
          return answer is Response
              ? Stream.value(answer)
              : Stream.error(answer);
        }),
        cache: GraphQLCache(),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          unauthenticatedGraphQlClientProvider.overrideWithValue(client),
        ],
      );
      container.read(authCredentialsStoreProvider.future);
      async.flushMicrotasks();
      body(async, container, calls, client);
      container.dispose();
    });
  }

  /// Starts the gate and settles it, returning its token or its error.
  Object? gate(
    FakeAsync async,
    ProviderContainer container,
    GraphQLClient client,
  ) {
    Object? result;
    container
        .read(authCoordinatorProvider.notifier)
        .usableUiAccessToken(gqlClient: () => client, trigger: 'test')
        .then<void>(
          (token) => result = token,
          onError: (Object e) => result = e,
        );
    async.flushMicrotasks();
    return result;
  }

  test('a live token goes out without a refresh', () {
    withStore(fresh, const [], (async, container, calls, client) {
      expect(gate(async, container, client), fresh);
      expect(calls, isEmpty);
    });
  });

  test('a token about to expire is refreshed first', () {
    final due = _jwt(const Duration(seconds: 30));
    withStore(due, [_success(fresh)], (async, container, calls, client) {
      expect(gate(async, container, client), fresh);
      expect(calls, hasLength(1));
    });
  });

  test('an expired token gets a second refresh attempt', () {
    final expired = _jwt(const Duration(minutes: -78));
    withStore(expired, [_unreachable, _success(fresh)], (
      async,
      container,
      calls,
      client,
    ) {
      expect(gate(async, container, client), fresh);
      expect(calls, hasLength(2));
    });
  });

  test('concurrent requests share both refresh attempts', () {
    final expired = _jwt(const Duration(minutes: -5));
    withStore(expired, [_unreachable, _success(fresh)], (
      async,
      container,
      calls,
      client,
    ) {
      final coordinator = container.read(authCoordinatorProvider.notifier);
      final tokens = <String?>[];
      for (var i = 0; i < 5; i++) {
        coordinator
            .usableUiAccessToken(gqlClient: () => client, trigger: 'test')
            .then(tokens.add);
      }
      async.flushMicrotasks();
      expect(tokens, List.filled(5, fresh));
      expect(calls, hasLength(2));
    });
  });

  group('endpoint handover', () {});
}
