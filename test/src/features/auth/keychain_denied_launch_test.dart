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
  }) async => store[key];

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

      c.invalidate(credentialsProvider);
      await c.read(credentialsProvider.future);
      expect(storage.reads, 1, reason: 'a refused keychain is not asked again');
    },
  );

  test(
    'a refused replacement signs out next launch instead of restoring the old account',
    () async {
      final backing = <String, String>{
        'auth.ui.accessToken': 'old-access',
        'auth.ui.refreshToken': 'old-refresh',
      };
      final storage = _FlakyStorage(backing)..failWrites = true;
      final first = _container(storage);
      await first.read(authCredentialsStoreProvider.future);

      await first
          .read(authCredentialsStoreProvider.notifier)
          .saveUiLoginTokens(
            accessToken: 'new-access',
            refreshToken: 'new-refresh',
          );

      // The write was refused: the old account is still in storage.
      expect(backing['auth.ui.accessToken'], 'old-access');
      expect(_invalidated(), isTrue);

      // Next launch, keychain working again. The unknown-on-disk state must
      // not be handed to the user as the previous account.
      debugResetKeychainRefusal();
      final restarted = _container(_FlakyStorage(backing));
      final state = await restarted.read(authCredentialsStoreProvider.future);
      expect(state.uiAccessToken, isNull);
      expect(state.uiRefreshToken, isNull);
      expect(backing, isEmpty);
      expect(_invalidated(), isFalse);
    },
  );

}
