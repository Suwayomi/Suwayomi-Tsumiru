// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/basic_auth_migration.dart';
import 'package:tsumiru/src/features/auth/data/custom_headers_store.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';
import 'package:tsumiru/src/features/offline/data/background/record_seal.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';

class _DeniedStorage implements FlutterSecureStorage {
  int reads = 0;
  final List<String> writes = [];

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
    reads++;
    throw PlatformException(code: '-128', message: 'User canceled');
  }

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
  }) async => writes.add(key);

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _InMemoryStorage implements FlutterSecureStorage {
  _InMemoryStorage(this._store);
  final Map<String, String> _store;

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
  }) async {}

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

ProviderContainer _container(FlutterSecureStorage storage) {
  final container = ProviderContainer(
    overrides: [secureStorageProvider.overrideWithValue(storage)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(debugResetKeychainRefusal);

  test(
    'a refused keychain read leaves the credentials absent instead of stalling startup',
    () async {
      final container = _container(_DeniedStorage());

      final auth = await container
          .read(authCredentialsStoreProvider.future)
          .timeout(const Duration(seconds: 5));
      final basic = await container
          .read(credentialsProvider.future)
          .timeout(const Duration(seconds: 5));
      final headers = await container
          .read(customHttpHeadersProvider.future)
          .timeout(const Duration(seconds: 5));

      expect(auth.uiAccessToken, isNull);
      expect(auth.uiRefreshToken, isNull);
      expect(auth.simpleLoginCookie, isNull);
      expect(basic, isNull);
      expect(headers, isEmpty);
    },
  );

  test('startup asks the keychain once when it refuses a read', () async {
    final storage = _DeniedStorage();
    final container = _container(storage);

    final auth = await container
        .read(authCredentialsStoreProvider.future)
        .timeout(const Duration(seconds: 5));
    final basic = await container
        .read(credentialsProvider.future)
        .timeout(const Duration(seconds: 5));
    final headers = await container
        .read(customHttpHeadersProvider.future)
        .timeout(const Duration(seconds: 5));

    expect(storage.reads, 1);
    expect(auth.uiAccessToken, isNull);
    expect(basic, isNull);
    expect(headers, isEmpty);
  });

  test('a refused keychain never creates a new record key', () async {
    RecordSeal.debugKey = null;
    final storage = _DeniedStorage();
    await RecordSeal.load(
      storage,
      create: true,
    ).timeout(const Duration(seconds: 5));
    expect(RecordSeal.ready, isFalse);
    expect(storage.reads, 1);
    expect(storage.writes, isEmpty);
  });

  test('a refused keychain read is not retried', () async {
    final storage = _DeniedStorage();
    final container = _container(storage);

    await container
        .read(authCredentialsStoreProvider.future)
        .timeout(const Duration(seconds: 5));
    await container
        .read(credentialsProvider.future)
        .timeout(const Duration(seconds: 5));
    final readsAfterLoad = storage.reads;

    await Future<void>.delayed(const Duration(seconds: 2));

    expect(storage.reads, readsAfterLoad);
  });

  test('a readable keychain still loads the stored credentials', () async {
    final container = _container(
      _InMemoryStorage({
        'auth.simple.cookie': 'JSESSIONID=abc123',
        kBasicCredentialsSecureKey: 'Basic abc',
      }),
    );

    final auth = await container.read(authCredentialsStoreProvider.future);
    final basic = await container.read(credentialsProvider.future);

    expect(auth.simpleLoginCookie, 'JSESSIONID=abc123');
    expect(basic, 'Basic abc');
  });
}
