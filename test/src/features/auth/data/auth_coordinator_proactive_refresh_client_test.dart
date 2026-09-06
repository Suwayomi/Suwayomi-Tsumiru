// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

/// Builds a minimal JWT with the given payload. Signature is a fixed
/// placeholder; the decoder doesn't verify it. Mirrors the helper in
/// auth_credentials_store_test.dart.
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
  }) async =>
      _store[key];

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

/// Test-only stand-in for "the live GraphQLClient changed" (e.g. a server
/// switch, an auth-link rebuild): [graphQlClientProvider] is overridden to
/// rebuild from [port], and each rebuild records the port it used in [built]
/// — flipping [port] then calling `container.invalidate(graphQlClientProvider)`
/// simulates the provider's dependencies changing.
class _FakeClientSource {
  int port = 1;
  final built = <int>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a fired proactive refresh reads the CURRENT graphQlClientProvider, '
    'not the one captured when it was scheduled',
    () async {
      debugResetAuthCoordinatorSingleFlight();

      // Already-expired so the computed proactive-refresh delay clamps to
      // Duration.zero — the Timer fires on the next event-loop turn instead
      // of needing a real (or faked) wait.
      final expiredJwt = _buildJwt({
        'exp': DateTime.now()
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
      final container = ProviderContainer(overrides: [
        secureStorageProvider.overrideWithValue(storage),
        graphQlClientProvider.overrideWith((ref) {
          source.built.add(source.port);
          // Loopback + a closed/unused port: the mutation attempt fails fast
          // with connection-refused; we only care that THIS client (built
          // from the CURRENT port) is the one the refresh call receives, not
          // that the mutation itself succeeds.
          return GraphQLClient(
            link: HttpLink('http://127.0.0.1:${source.port}'),
            cache: GraphQLCache(),
          );
        }),
      ]);
      addTearDown(container.dispose);

      // Hydrate the credentials store BEFORE constructing AuthCoordinator, so
      // its build()'s `ref.listen(..., fireImmediately: true)` sees an
      // already-resolved (non-loading) state on the very first call.
      await container.read(authCredentialsStoreProvider.future);

      // Triggers AuthCoordinator.build(): the listener above fires
      // immediately, schedules the proactive-refresh Timer at delay zero.
      container.read(authCoordinatorProvider.notifier);

      // Simulate the client changing AFTER the refresh was scheduled but
      // BEFORE it fires (a server switch landing in that window).
      source.port = 2;
      container.invalidate(graphQlClientProvider);

      // Let the zero-delay Timer fire and the resulting (fast, local,
      // connection-refused) mutation attempt resolve.
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        source.built.contains(2),
        isTrue,
        reason: 'the fired refresh must have read graphQlClientProvider '
            'again to pick up port 2 — before the fix it kept using '
            'whatever client was live when the Timer was first scheduled '
            '(port 1, or no read at all), forever.',
      );
      expect(
        source.built.last,
        2,
        reason: 'the LAST client built must be the current one at fire '
            'time, not a stale one from scheduling time',
      );
    },
  );
}
