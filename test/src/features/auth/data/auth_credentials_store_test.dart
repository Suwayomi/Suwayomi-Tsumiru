// Copyright (c) 2026 Contributors to the Suwayomi project

import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';

/// Builds a minimal JWT with the given payload. Signature is a fixed
/// placeholder; the decoder doesn't verify.
String _buildJwt(Map<String, dynamic> payload) {
  String b64Url(String s) =>
      base64Url.encode(utf8.encode(s)).replaceAll('=', '');
  return '${b64Url('{"alg":"HS256"}')}.${b64Url(jsonEncode(payload))}.sig';
}

class _InMemorySecureStorage implements FlutterSecureStorage {
  _InMemorySecureStorage([Map<String, String>? seed]) : _store = {...?seed};
  final Map<String, String> _store;
  Completer<void>? readBarrier;

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
  }) async {
    final value = _store[key];
    await readBarrier?.future;
    return value;
  }

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

ProviderContainer _container(_InMemorySecureStorage storage) =>
    ProviderContainer(
      overrides: [secureStorageProvider.overrideWithValue(storage)],
    );

void main() {
  const binding = AccountBinding(
    address: 'https://server:443',
    userId: 2,
    username: 'Reader',
    catalogId: 'catalog-reader',
  );
  test(
    'verified binding survives access and pair refresh and restart',
    () async {
      final storage = _InMemorySecureStorage();
      final container = _container(storage);
      addTearDown(container.dispose);
      final store = container.read(authCredentialsStoreProvider.notifier);
      await store.saveUiLoginTokens(
        accessToken: 'A',
        refreshToken: 'R',
        binding: binding,
      );
      await store.updateUiLoginAccessToken('A2', forEpoch: store.serverEpoch);
      expect(
        await store.refreshUiLoginTokens(
          accessToken: 'A3',
          refreshToken: 'R2',
          originalRefreshToken: 'R',
          forEpoch: store.serverEpoch,
        ),
        isTrue,
      );
      final restored = _container(storage);
      addTearDown(restored.dispose);
      final credentials = await restored.read(
        authCredentialsStoreProvider.future,
      );
      expect(credentials.accountBinding?.catalogId, 'catalog-reader');
      expect(credentials.accountBinding?.userId, 2);
      expect(credentials.uiAccessToken, 'A3');
      expect(credentials.uiRefreshToken, 'R2');
    },
  );
  test(
    'unverified replacement cannot retain previous account ownership',
    () async {
      final storage = _InMemorySecureStorage();
      final container = _container(storage);
      addTearDown(container.dispose);
      final store = container.read(authCredentialsStoreProvider.notifier);
      await store.saveUiLoginTokens(
        accessToken: 'A',
        refreshToken: 'R',
        binding: binding,
      );
      await store.saveUiLoginTokens(accessToken: 'B', refreshToken: 'RB');
      expect(
        container
            .read(authCredentialsStoreProvider)
            .requireValue
            .accountBinding,
        isNull,
      );
      final restored = _container(storage);
      addTearDown(restored.dispose);
      expect(
        (await restored.read(
          authCredentialsStoreProvider.future,
        )).accountBinding,
        isNull,
      );
    },
  );
  test('interrupted pair write fails closed on restart', () async {
    final storage = _InMemorySecureStorage({
      'auth.ui.accessToken': 'B',
      'auth.ui.refreshToken': 'R',
      'auth.ui.accountBinding': binding.encode(
        accessToken: 'A',
        refreshToken: 'R',
      ),
    });
    final container = _container(storage);
    addTearDown(container.dispose);
    expect(
      (await container.read(
        authCredentialsStoreProvider.future,
      )).accountBinding,
      isNull,
    );
  });

  test('session observers close admission before credentials change', () async {
    final c = _container(_InMemorySecureStorage());
    addTearDown(c.dispose);
    await c.read(authCredentialsStoreProvider.future);
    final store = c.read(authCredentialsStoreProvider.notifier);
    final observed = <(int, bool)>[];
    c.listen(authCredentialsStoreProvider, (_, next) {
      if (next.value case final value?) {
        observed.add((value.sessionEpoch, value.sessionChanging));
      }
    });
    final entered = Completer<void>();
    final finish = Completer<void>();
    final change = store.withIdentityChange(() async {
      entered.complete();
      await finish.future;
    });
    await entered.future;
    expect(observed, isNotEmpty);
    expect(observed.last.$2, isTrue);
    final changingEpoch = observed.last.$1;
    finish.complete();
    await change;
    expect(observed.last.$2, isFalse);
    expect(observed.last.$1, greaterThan(changingEpoch));
    await store.saveUiLoginTokens(accessToken: 'A', refreshToken: 'R');
    final settled = observed.last;
    await store.updateUiLoginAccessToken('A2');
    expect(observed.last, settled);
  });

  test(
    'direct credential replacement invalidates the previous session',
    () async {
      final c = _container(_InMemorySecureStorage());
      addTearDown(c.dispose);
      await c.read(authCredentialsStoreProvider.future);
      final store = c.read(authCredentialsStoreProvider.notifier);
      var previous = store.sessionEpoch;
      await store.saveUiLoginTokens(accessToken: 'A', refreshToken: 'R');
      expect(store.sessionEpoch, greaterThan(previous));
      previous = store.sessionEpoch;
      await store.saveSimpleLoginCookie('cookie-B');
      expect(store.sessionEpoch, greaterThan(previous));
    },
  );

  test(
    'worker refresh preserves its session and rejects a previous account',
    () async {
      final c = _container(_InMemorySecureStorage());
      addTearDown(c.dispose);
      await c.read(authCredentialsStoreProvider.future);
      final store = c.read(authCredentialsStoreProvider.notifier);
      await store.saveUiLoginTokens(accessToken: 'A', refreshToken: 'R-A');
      final epoch = store.sessionEpoch;
      await store.refreshUiLoginTokens(
        accessToken: 'A2',
        refreshToken: 'R-A2',
        originalRefreshToken: 'R-A',
        forEpoch: store.serverEpoch,
      );
      expect(store.uiLoginTokens()?.accessToken, 'A2');
      expect(store.sessionEpoch, epoch);
      await store.saveUiLoginTokens(accessToken: 'B', refreshToken: 'R-B');
      await store.refreshUiLoginTokens(
        accessToken: 'A3',
        refreshToken: 'R-A3',
        originalRefreshToken: 'R-A',
        forEpoch: store.serverEpoch,
      );
      expect(store.uiLoginTokens()?.accessToken, 'B');
      expect(store.uiLoginTokens()?.refreshToken, 'R-B');
    },
  );

  test(
    'epoch-bound replacement cannot queue behind another identity change',
    () async {
      final c = _container(_InMemorySecureStorage());
      addTearDown(c.dispose);
      await c.read(authCredentialsStoreProvider.future);
      final store = c.read(authCredentialsStoreProvider.notifier);
      final entered = Completer<void>();
      final release = Completer<void>();
      final change = store.withIdentityChange(() async {
        entered.complete();
        await release.future;
        await store.saveUiLoginTokens(accessToken: 'B', refreshToken: 'R-B');
      });
      await entered.future;
      final stale = store.saveUiLoginTokens(
        accessToken: 'A',
        refreshToken: 'R-A',
        forEpoch: store.serverEpoch,
      );
      release.complete();
      await Future.wait([change, stale]);
      expect(store.uiLoginTokens()?.accessToken, 'B');
    },
  );

  test('replacement waits for initial credential hydration', () async {
    final storage = _InMemorySecureStorage({
      'auth.ui.accessToken': 'A',
      'auth.ui.refreshToken': 'R-A',
    })..readBarrier = Completer<void>();
    final c = _container(storage);
    addTearDown(c.dispose);
    final loading = c.read(authCredentialsStoreProvider.future);
    final store = c.read(authCredentialsStoreProvider.notifier);
    final replacement = store.saveUiLoginTokens(
      accessToken: 'B',
      refreshToken: 'R-B',
    );
    await pumpEventQueue();
    storage.readBarrier!.complete();
    await Future.wait([loading, replacement]);
    expect(
      c.read(authCredentialsStoreProvider).requireValue.uiAccessToken,
      'B',
    );
    expect(await storage.read(key: 'auth.ui.accessToken'), 'B');
  });

  test('basic logout clears the loaded credential provider', () async {
    final storage = _InMemorySecureStorage({
      'auth.basic.credentials': 'Basic A',
    });
    final c = _container(storage);
    addTearDown(c.dispose);
    final subscription = c.listen(credentialsProvider, (_, _) {});
    addTearDown(subscription.close);
    expect(await c.read(credentialsProvider.future), 'Basic A');
    await c.read(authCredentialsStoreProvider.future);
    await c.read(authCredentialsStoreProvider.notifier).clearBasicCredentials();
    expect(await c.read(credentialsProvider.future), isNull);
    expect(await storage.read(key: 'auth.basic.credentials'), isNull);
  });

  for (final replacement in ['Basic B', null]) {
    test(
      'basic credential mutation waits for initial hydration: $replacement',
      () async {
        final storage = _InMemorySecureStorage({
          'auth.basic.credentials': 'Basic A',
        })..readBarrier = Completer<void>();
        final c = _container(storage);
        addTearDown(c.dispose);
        final subscription = c.listen(credentialsProvider, (_, _) {});
        addTearDown(subscription.close);
        final loading = c.read(credentialsProvider.future);
        final change = c.read(credentialsProvider.notifier).set(replacement);
        await pumpEventQueue();
        storage.readBarrier!.complete();
        await Future.wait([loading, change]);
        expect(await c.read(credentialsProvider.future), replacement);
        expect(await storage.read(key: 'auth.basic.credentials'), replacement);
      },
    );
  }

  group('AuthCredentialsStore — build() (load from secure storage)', () {
    test(
      'build loads existing values from secure storage into state',
      () async {
        final storage = _InMemorySecureStorage({
          'auth.ui.accessToken': 'A',
          'auth.ui.refreshToken': 'R',
          'auth.simple.cookie': 'JSESSIONID=abc',
          'auth.password': 'hunter2',
        });
        final c = _container(storage);
        addTearDown(c.dispose);

        final state = await c.read(authCredentialsStoreProvider.future);
        expect(state.uiAccessToken, 'A');
        expect(state.uiRefreshToken, 'R');
        expect(state.simpleLoginCookie, 'JSESSIONID=abc');
        expect(state.password, 'hunter2');
      },
    );

    test('build returns empty state when nothing is stored', () async {
      final storage = _InMemorySecureStorage();
      final c = _container(storage);
      addTearDown(c.dispose);

      final state = await c.read(authCredentialsStoreProvider.future);
      expect(state.uiAccessToken, isNull);
      expect(state.simpleLoginCookie, isNull);
    });
  });

  group('AuthCredentialsStore — UI Login', () {
    test('saveUiLoginTokens persists AND updates state', () async {
      final storage = _InMemorySecureStorage();
      final c = _container(storage);
      addTearDown(c.dispose);

      // Force build so the notifier exists.
      await c.read(authCredentialsStoreProvider.future);

      final store = c.read(authCredentialsStoreProvider.notifier);
      await store.saveUiLoginTokens(
        accessToken: 'ACCESS123',
        refreshToken: 'REFRESH456',
      );

      // Backing store written.
      expect(await storage.read(key: 'auth.ui.accessToken'), 'ACCESS123');
      expect(await storage.read(key: 'auth.ui.refreshToken'), 'REFRESH456');
      // Riverpod state updated synchronously (no reload needed).
      final state = c.read(authCredentialsStoreProvider).requireValue;
      expect(state.uiAccessToken, 'ACCESS123');
      expect(state.uiRefreshToken, 'REFRESH456');
      // Convenience header projection.
      expect(state.uiAuthorizationHeader, {
        'Authorization': 'Bearer ACCESS123',
      });
    });

    test(
      'clearUiLoginTokens removes both tokens from store AND state',
      () async {
        final storage = _InMemorySecureStorage({
          'auth.ui.accessToken': 'A',
          'auth.ui.refreshToken': 'R',
        });
        final c = _container(storage);
        addTearDown(c.dispose);
        await c.read(authCredentialsStoreProvider.future);

        final store = c.read(authCredentialsStoreProvider.notifier);
        await store.clearUiLoginTokens();

        expect(await storage.read(key: 'auth.ui.accessToken'), isNull);
        expect(await storage.read(key: 'auth.ui.refreshToken'), isNull);
        final state = c.read(authCredentialsStoreProvider).requireValue;
        expect(state.uiAccessToken, isNull);
        expect(state.uiAuthorizationHeader, isNull);
      },
    );

    test('updateUiLoginAccessToken updates only the access token', () async {
      final storage = _InMemorySecureStorage({
        'auth.ui.accessToken': 'OLD',
        'auth.ui.refreshToken': 'REFRESH',
      });
      final c = _container(storage);
      addTearDown(c.dispose);
      await c.read(authCredentialsStoreProvider.future);

      final store = c.read(authCredentialsStoreProvider.notifier);
      await store.updateUiLoginAccessToken('NEW');

      final state = c.read(authCredentialsStoreProvider).requireValue;
      expect(state.uiAccessToken, 'NEW');
      expect(
        state.uiRefreshToken,
        'REFRESH',
        reason: 'refresh token must not be touched on access rotation',
      );
    });

    test(
      'saveUiLoginTokens populates uiAccessTokenExpiresAt from JWT',
      () async {
        // JWT with exp=1800000000 (2027-01-15 08:00 UTC).
        const expTs = 1800000000;
        final jwt = _buildJwt({'exp': expTs});

        final storage = _InMemorySecureStorage();
        final c = _container(storage);
        addTearDown(c.dispose);
        await c.read(authCredentialsStoreProvider.future);

        final store = c.read(authCredentialsStoreProvider.notifier);
        await store.saveUiLoginTokens(accessToken: jwt, refreshToken: 'R');

        final state = c.read(authCredentialsStoreProvider).requireValue;
        expect(state.uiAccessTokenExpiresAt, isNotNull);
        expect(
          state.uiAccessTokenExpiresAt!.millisecondsSinceEpoch,
          expTs * 1000,
        );
        expect(state.uiAccessTokenExpiresAt!.isUtc, isTrue);
      },
    );

    test('updateUiLoginAccessToken refreshes the expiry timestamp', () async {
      final oldJwt = _buildJwt({'exp': 1700000000});
      final newJwt = _buildJwt({'exp': 1800000000});
      final storage = _InMemorySecureStorage({
        'auth.ui.accessToken': oldJwt,
        'auth.ui.refreshToken': 'R',
      });
      final c = _container(storage);
      addTearDown(c.dispose);
      await c.read(authCredentialsStoreProvider.future);

      final store = c.read(authCredentialsStoreProvider.notifier);
      await store.updateUiLoginAccessToken(newJwt);

      final state = c.read(authCredentialsStoreProvider).requireValue;
      expect(
        state.uiAccessTokenExpiresAt!.millisecondsSinceEpoch,
        1800000000 * 1000,
      );
    });

    test('clearUiLoginTokens also clears uiAccessTokenExpiresAt', () async {
      final jwt = _buildJwt({'exp': 1800000000});
      final storage = _InMemorySecureStorage({
        'auth.ui.accessToken': jwt,
        'auth.ui.refreshToken': 'R',
      });
      final c = _container(storage);
      addTearDown(c.dispose);
      await c.read(authCredentialsStoreProvider.future);

      final store = c.read(authCredentialsStoreProvider.notifier);
      // Expiry should have been seeded on bootstrap.
      expect(
        c
            .read(authCredentialsStoreProvider)
            .requireValue
            .uiAccessTokenExpiresAt,
        isNotNull,
      );

      await store.clearUiLoginTokens();
      final state = c.read(authCredentialsStoreProvider).requireValue;
      expect(state.uiAccessTokenExpiresAt, isNull);
    });

    test('saveUiLoginTokens with malformed JWT leaves expiry null AND '
        'clears any stale expiry from a previous good token', () async {
      final goodJwt = _buildJwt({'exp': 1800000000});
      final storage = _InMemorySecureStorage({
        'auth.ui.accessToken': goodJwt,
        'auth.ui.refreshToken': 'R',
      });
      final c = _container(storage);
      addTearDown(c.dispose);
      await c.read(authCredentialsStoreProvider.future);

      // Sanity: expiry was decoded.
      expect(
        c
            .read(authCredentialsStoreProvider)
            .requireValue
            .uiAccessTokenExpiresAt,
        isNotNull,
      );

      // Overwrite with a malformed token.
      final store = c.read(authCredentialsStoreProvider.notifier);
      await store.saveUiLoginTokens(
        accessToken: 'not-a-jwt',
        refreshToken: 'R2',
      );

      final state = c.read(authCredentialsStoreProvider).requireValue;
      expect(state.uiAccessToken, 'not-a-jwt');
      expect(
        state.uiAccessTokenExpiresAt,
        isNull,
        reason: 'stale expiry from the previous valid token must not survive',
      );
    });

    test(
      'build() seeds uiAccessTokenExpiresAt from stored access token',
      () async {
        final jwt = _buildJwt({'exp': 1800000000});
        final storage = _InMemorySecureStorage({
          'auth.ui.accessToken': jwt,
          'auth.ui.refreshToken': 'R',
        });
        final c = _container(storage);
        addTearDown(c.dispose);
        await c.read(authCredentialsStoreProvider.future);

        final state = c.read(authCredentialsStoreProvider).requireValue;
        expect(
          state.uiAccessTokenExpiresAt!.millisecondsSinceEpoch,
          1800000000 * 1000,
        );
      },
    );
  });

  group('AuthCredentialsStore — Simple Login', () {
    test('saveSimpleLoginCookie persists AND updates state', () async {
      final storage = _InMemorySecureStorage();
      final c = _container(storage);
      addTearDown(c.dispose);
      await c.read(authCredentialsStoreProvider.future);

      final store = c.read(authCredentialsStoreProvider.notifier);
      await store.saveSimpleLoginCookie('JSESSIONID=abc123');

      final state = c.read(authCredentialsStoreProvider).requireValue;
      expect(state.simpleLoginCookie, 'JSESSIONID=abc123');
      expect(state.simpleLoginCookieHeader, {'Cookie': 'JSESSIONID=abc123'});
    });

    test(
      'clearSimpleLoginCookie removes the cookie from store + state',
      () async {
        final storage = _InMemorySecureStorage({
          'auth.simple.cookie': 'JSESSIONID=x',
        });
        final c = _container(storage);
        addTearDown(c.dispose);
        await c.read(authCredentialsStoreProvider.future);

        final store = c.read(authCredentialsStoreProvider.notifier);
        await store.clearSimpleLoginCookie();

        final state = c.read(authCredentialsStoreProvider).requireValue;
        expect(state.simpleLoginCookie, isNull);
        expect(state.simpleLoginCookieHeader, isNull);
      },
    );
  });

  group('AuthCredentialsStore — password', () {
    test('savePassword persists AND updates state', () async {
      final storage = _InMemorySecureStorage();
      final c = _container(storage);
      addTearDown(c.dispose);
      await c.read(authCredentialsStoreProvider.future);

      final store = c.read(authCredentialsStoreProvider.notifier);
      await store.savePassword('hunter2');

      expect(await storage.read(key: 'auth.password'), 'hunter2');
      expect(
        c.read(authCredentialsStoreProvider).requireValue.password,
        'hunter2',
      );
    });
  });

  group('AuthCredentialsStore — basic credentials (migrated)', () {
    test('clearBasicCredentials removes the secure-storage entry', () async {
      final storage = _InMemorySecureStorage({
        'auth.basic.credentials': 'Basic YWFyb246aHVudGVyMg==',
      });
      final c = _container(storage);
      addTearDown(c.dispose);
      await c.read(authCredentialsStoreProvider.future);

      final store = c.read(authCredentialsStoreProvider.notifier);
      await store.clearBasicCredentials();

      expect(await storage.read(key: 'auth.basic.credentials'), isNull);
    });
  });
}
