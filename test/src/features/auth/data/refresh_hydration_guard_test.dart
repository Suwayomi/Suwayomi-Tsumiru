// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/auth_state.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';

/// Secure storage whose reads never complete — the credentials store stays
/// un-hydrated for the whole test, like a slow platform keystore at startup.
class _HangingStorage extends Fake implements FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) =>
      Completer<String?>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('refresh before the credentials store hydrates is transient, '
      'not "Session expired"', () async {
    debugResetAuthCoordinatorSingleFlight();
    final container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(_HangingStorage()),
    ]);
    addTearDown(container.dispose);

    final gql = GraphQLClient(
      link: HttpLink('http://localhost:1'),
      cache: GraphQLCache(),
    );
    final outcome = await container
        .read(authCoordinatorProvider.notifier)
        .refreshUiAccessToken(gqlClient: gql);

    // The tokens may well exist on disk — the store just hasn't loaded them.
    // Declaring the session dead here is the false "Session expired" banner.
    expect(outcome, isA<RefreshTransientFailure>());
    expect(container.read(needsReauthProvider), isFalse);
  });
}
