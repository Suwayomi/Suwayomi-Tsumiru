// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../../settings/presentation/server/widget/credential_popup/login_credentials_popup.dart';
import '../data/auth_coordinator.dart';
import '../data/auth_credentials_store.dart';
import '../data/auth_state.dart';

/// The single sign-in routine shared by first-run onboarding and the
/// Connection settings screen. Neither surface reimplements login — they both
/// call this so the wizard and the settings page behave identically.
///
/// Records the username, clears the other auth modes' stored credentials (so a
/// mode switch can't leave a stale token behind), then commits via the matching
/// canonical path:
///   * basic       — store the `Basic` header (no round-trip; validated by the
///                   next real request, exactly as the settings screen does),
///   * simpleLogin — [AuthCoordinator.loginSimple] (verifies + persists cookie),
///   * uiLogin     — [AuthCoordinator.loginUi]     (verifies + persists tokens).
///
/// Throws on rejection for ui/simple (bad credentials or wrong auth mode); the
/// caller surfaces the error.
Future<void> performSignIn(
  WidgetRef ref, {
  required AuthType authType,
  required String serverBaseUrl,
  required String username,
  required String password,
}) async {
  ref.read(authUsernameProvider.notifier).update(username);
  final store = ref.read(authCredentialsStoreProvider.notifier);
  // Guards every write below against a server switch racing this sign-in.
  final epoch = store.serverEpoch;
  if (authType != AuthType.uiLogin) await store.clearUiLoginTokens();
  if (authType != AuthType.simpleLogin) await store.clearSimpleLoginCookie();
  if (authType != AuthType.basic) await store.clearBasicCredentials();

  final coordinator = ref.read(authCoordinatorProvider.notifier);
  switch (authType) {
    case AuthType.basic:
      await ref.read(credentialsProvider.notifier).set(
          'Basic ${base64.encode(utf8.encode('$username:$password'))}',
          forEpoch: epoch);
    case AuthType.simpleLogin:
      await coordinator.loginSimple(
        serverBaseUrl: serverBaseUrl,
        username: username,
        password: password,
      );
    case AuthType.uiLogin:
      await coordinator.loginUi(
        gqlClient: ref.read(graphQlClientProvider),
        username: username,
        password: password,
      );
    case AuthType.none:
      return;
  }
  ref.read(needsReauthProvider.notifier).set(false);
}
