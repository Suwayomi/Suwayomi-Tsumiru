// Copyright (c) 2026 Contributors to the Suwayomi project

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

/// Builds a minimal JWT with the given payload. Signature is a fixed
/// placeholder; the decoder doesn't verify.

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

late SharedPreferences _prefs;

ProviderContainer _container(_InMemorySecureStorage storage) =>
    ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        sharedPreferencesProvider.overrideWithValue(_prefs),
      ],
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

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

  test('tokens save and clear in store and state, and a legacy password is '
      'deleted at launch', () async {
    final storage = _InMemorySecureStorage({'auth.password': 'hunter2'});
    final c = _container(storage);
    addTearDown(c.dispose);
    await c.read(authCredentialsStoreProvider.future);
    await pumpEventQueue();
    expect(await storage.read(key: 'auth.password'), isNull);

    final store = c.read(authCredentialsStoreProvider.notifier);
    await store.saveUiLoginTokens(
      accessToken: 'ACCESS123',
      refreshToken: 'REFRESH456',
    );

    expect(await storage.read(key: 'auth.ui.accessToken'), 'ACCESS123');
    expect(await storage.read(key: 'auth.ui.refreshToken'), 'REFRESH456');
    var state = c.read(authCredentialsStoreProvider).requireValue;
    expect(state.uiAccessToken, 'ACCESS123');
    expect(state.uiRefreshToken, 'REFRESH456');
    expect(state.uiAuthorizationHeader, {'Authorization': 'Bearer ACCESS123'});

    await store.clearUiLoginTokens();

    expect(await storage.read(key: 'auth.ui.accessToken'), isNull);
    expect(await storage.read(key: 'auth.ui.refreshToken'), isNull);
    state = c.read(authCredentialsStoreProvider).requireValue;
    expect(state.uiAccessToken, isNull);
    expect(state.uiAuthorizationHeader, isNull);
  });

  group('AuthCredentialsStore — build() (load from secure storage)', () {});

  group('AuthCredentialsStore — basic credentials (migrated)', () {});
}
