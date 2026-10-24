// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/misc/toast/toast.dart';
import '../../offline/data/background/background_download_controller_shim.dart';
import '../../settings/presentation/server/widget/credential_popup/login_credentials_popup.dart';
import '../../settings/presentation/server/widget/sign_in/graphql/__generated__/sign_in.graphql.dart';
import '../data/auth_coordinator.dart';
import '../data/auth_credentials_store.dart';
import '../data/auth_recovery_target.dart';
import '../data/auth_state.dart';
import '../data/secure_credentials_provider.dart';

/// The single sign-in routine shared by first-run onboarding and the
/// Connection settings screen. Neither surface reimplements login — they both
/// call this so the wizard and the settings page behave identically.
///
/// Verifies and adopts the new sign-in before clearing obsolete credentials:
///   * basic       — [AuthCoordinator.loginBasic] (verifies + persists header),
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
}) {
  // The notice below belongs to this attempt, not to an earlier one.
  resetCredentialWriteFailure();
  return ref.read(backgroundDownloadControllerProvider).changeIdentity(() async {
    final store = ref.read(authCredentialsStoreProvider.notifier);

    final coordinator = ref.read(authCoordinatorProvider.notifier);
    switch (authType) {
      case AuthType.basic:
        // Verifies before persisting, like the other two modes: basic_auth has
        // no login round-trip, so storing blind reported a successful sign-in
        // for credentials the server refuses.
        await coordinator.loginBasic(
          serverBaseUrl: serverBaseUrl,
          username: username,
          password: password,
        );
      case AuthType.simpleLogin:
        await coordinator.loginSimple(
          serverBaseUrl: serverBaseUrl,
          username: username,
          password: password,
        );
      case AuthType.uiLogin:
        await coordinator.loginUi(
          gqlClient: ref.read(unauthenticatedGraphQlClientProvider),
          username: username,
          password: password,
          serverBaseUrl: serverBaseUrl,
        );
      case AuthType.none:
        final status = await ref
            .read(unauthenticatedGraphQlClientProvider)
            .query$ServerSignInStatus(
              Options$Query$ServerSignInStatus(
                fetchPolicy: FetchPolicy.noCache,
              ),
            )
            .getData((data) => data.settings);
        if (status == null) {
          throw StateError('Could not verify anonymous access');
        }
    }
    if (authType != AuthType.uiLogin) await store.clearUiLoginTokens();
    if (authType != AuthType.simpleLogin) await store.clearSimpleLoginCookie();
    if (authType != AuthType.basic) await store.clearBasicCredentials();
    ref.read(authUsernameProvider.notifier).update(username);
    ref.read(authTypeKeyProvider.notifier).update(authType);
    ref.read(authRecoveryTargetProvider.notifier).set(null);
    ref.read(needsReauthProvider.notifier).set(false);
    // The sign-in works from memory for this run; say it cannot be saved
    // rather than leave the user expecting it next launch.
    if (credentialWriteFailedThisRun) {
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        ref.read(toastProvider)?.show(context.l10n.authCredentialsNotSaved);
      }
    }
  });
}
