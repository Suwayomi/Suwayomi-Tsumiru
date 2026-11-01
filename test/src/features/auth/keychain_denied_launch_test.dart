// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/custom_headers_store.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

/// A keychain that refuses every read, and optionally every write and delete.
class _DeniedStorage implements FlutterSecureStorage {
  _DeniedStorage();
  final bool failWrites = false;
  int reads = 0;
  int writeAttempts = 0;
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
  }) async {
    writeAttempts++;
    if (failWrites) {
      throw PlatformException(code: '-25293', message: 'User denied');
    }
    writes.add(key);
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
    if (failWrites) {
      throw PlatformException(code: '-25293', message: 'User denied');
    }
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// A readable, writable store whose writes or deletes can start failing, to
/// model the keychain refusing partway through a run.
class _FlakyStorage implements FlutterSecureStorage {
  _FlakyStorage(this.store) : failDeletes = false;
  final Map<String, String> store;
  bool failReads = false;
  bool failWrites = false;
  bool failDeletes;

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
    if (failReads) {
      throw PlatformException(
        code: 'Unexpected security result code',
        details: -128,
      );
    }
    return store[key];
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
  }) async {
    if (failWrites) {
      throw PlatformException(code: '-25293', message: 'User denied');
    }
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
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
    if (failDeletes) {
      throw PlatformException(code: '-25293', message: 'User denied');
    }
    store.remove(key);
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

late SharedPreferences _prefs;

ProviderContainer _container(FlutterSecureStorage storage) {
  final container = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      sharedPreferencesProvider.overrideWithValue(_prefs),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

bool _invalidated() =>
    _prefs.getBool(DBKeys.authCredentialsInvalidated.name) ?? false;

Future<void> _storeAccount(String username, AuthType type) async {
  await _prefs.setString(DBKeys.serverUrl.name, 'https://example.org');
  await _prefs.setBool(DBKeys.serverPortToggle.name, false);
  await _prefs.setString(DBKeys.authUsername.name, username);
  await _prefs.setInt(DBKeys.authType.name, type.index);
}

Future<void> _expectSignedOutAfterRestart(Map<String, String> backing) async {
  debugResetKeychainRefusal();
  final restarted = _container(_FlakyStorage(backing));
  final state = await restarted.read(authCredentialsStoreProvider.future);
  expect(state.uiAccessToken, isNull);
  expect(state.uiRefreshToken, isNull);
  expect(await restarted.read(credentialsProvider.future), isNull);
  expect(backing, isEmpty);
  expect(_invalidated(), isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    debugResetKeychainRefusal();
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  test(
    'a refused keychain is asked once and every credential reads absent',
    () async {
      final storage = _DeniedStorage();
      final c = _container(storage);

      final auth = await c
          .read(authCredentialsStoreProvider.future)
          .timeout(const Duration(seconds: 5));
      final basic = await c
          .read(credentialsProvider.future)
          .timeout(const Duration(seconds: 5));
      final headers = await c
          .read(customHttpHeadersProvider.future)
          .timeout(const Duration(seconds: 5));

      expect(storage.reads, 1);
      expect(auth.uiAccessToken, isNull);
      expect(auth.uiRefreshToken, isNull);
      expect(auth.simpleLoginCookie, isNull);
      expect(basic, isNull);
      expect(headers, isEmpty);
      expect(_invalidated(), isFalse);

      c.invalidate(credentialsProvider);
      await c.read(credentialsProvider.future);
      expect(storage.reads, 1, reason: 'a refused keychain is not asked again');
    },
  );

  test(
    'failed account switches still remove saved tokens next launch',
    () => Future.forEach([
      ('bob', AuthType.uiLogin),
      ('alice', AuthType.basic),
    ], (account) async {
      final (username, storedAuthType) = account;
      debugResetKeychainRefusal();
      await _storeAccount('alice', storedAuthType);
      final backing = <String, String>{
        'auth.ui.accessToken': 'old-access',
        'auth.ui.refreshToken': 'old-refresh',
        if (storedAuthType == AuthType.basic)
          'auth.basic.credentials': 'old-basic',
      };
      final storage = _FlakyStorage(backing)
        ..failReads = true
        ..failWrites = true
        ..failDeletes = true;
      final first = _container(storage);
      await first.read(authCredentialsStoreProvider.future);

      await first
          .read(authCredentialsStoreProvider.notifier)
          .saveUiLoginTokens(
            accessToken: 'new-access',
            refreshToken: 'new-refresh',
            binding: AccountBinding(
              address: 'https://example.org:443',
              username: username,
              catalogId: 'catalog',
            ),
          );

      expect(backing['auth.ui.accessToken'], 'old-access');
      expect(_invalidated(), isTrue);

      await _expectSignedOutAfterRestart(backing);
    }),
  );

  test(
    'same-account sign-in after refusal preserves the saved tokens',
    () async {
      await _storeAccount('Alice', AuthType.uiLogin);
      const binding = AccountBinding(
        address: 'https://example.org:443',
        username: 'alice',
        catalogId: 'catalog',
      );
      final backing = <String, String>{
        'auth.ui.accessToken': 'old-access',
        'auth.ui.refreshToken': 'old-refresh',
        'auth.ui.accountBinding': binding.encode(
          accessToken: 'old-access',
          refreshToken: 'old-refresh',
        ),
      };
      final storage = _FlakyStorage(backing)
        ..failReads = true
        ..failWrites = true;
      final first = _container(storage);
      await first.read(authCredentialsStoreProvider.future);

      final store = first.read(authCredentialsStoreProvider.notifier);
      await store.saveUiLoginTokens(
        accessToken: 'new-access',
        refreshToken: 'new-refresh',
        binding: binding,
      );
      debugResetKeychainRefusal();
      final restarted = _container(_FlakyStorage(backing));
      final restored = await restarted.read(authCredentialsStoreProvider.future);
      expect(restored.uiAccessToken, 'old-access');
      expect(restored.uiRefreshToken, 'old-refresh');
      expect(restored.accountBinding?.username, 'alice');
    },
  );

  test('failed sign-out after refusal removes saved tokens next launch', () async {
    final backing = <String, String>{
      'auth.ui.accessToken': 'old-access',
      'auth.ui.refreshToken': 'old-refresh',
    };
    final storage = _FlakyStorage(backing)
      ..failReads = true
      ..failDeletes = true;
    final first = _container(storage);
    await first.read(authCredentialsStoreProvider.future);
    await first.read(authCredentialsStoreProvider.notifier).clearUiLoginTokens();
    expect(_invalidated(), isTrue);

    await _expectSignedOutAfterRestart(backing);
  });

}
