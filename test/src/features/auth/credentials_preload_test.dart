// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/auth/data/basic_auth_migration.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';

class _InMemorySecureStorage implements FlutterSecureStorage {
  _InMemorySecureStorage([Map<String, String>? seed]) : _store = {...?seed};
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

void main() {
  // main() preloads the credentials, then images, links and background work
  // read `.value` synchronously. An auto-disposed provider dropped the
  // preload, so those reads saw null and the GraphQL client, on its first
  // watch, rebuilt under requests already on their way.
  test('the preloaded credentials are still there at the first read', () async {
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(
          _InMemorySecureStorage({kBasicCredentialsSecureKey: 'Basic abc'}),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(credentialsProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final state = container.read(credentialsProvider);
    expect(state.isLoading, isFalse);
    expect(state.value, 'Basic abc');
  });
}
