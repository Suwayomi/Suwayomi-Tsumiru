// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/db_keys.dart';
import '../../../../constants/endpoints.dart';
import '../../../../constants/enum.dart';
import '../../../../features/auth/data/auth_coordinator.dart';
import '../../../../features/auth/data/auth_credentials_store.dart';
import '../../../../features/auth/data/auth_state.dart';
import '../../../../features/auth/presentation/sign_in_action.dart';
import '../../../../global_providers/global_providers.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/section_title.dart';
import '../../../account/data/account_actions.dart';
import '../../../account/data/account_providers.dart';
import '../../../account/domain/account_access.dart';
import '../../../account/presentation/account_code_dialog.dart';
import '../../../auth/data/auth_session_status.dart';
import '../../../auth/presentation/auth_failure_text.dart';
import '../../../offline/data/background/background_download_controller_shim.dart';
import '../server/widget/client/server_port_tile/server_port_tile.dart';
import '../server/widget/client/server_url_tile/server_url_tile.dart';
import '../server/widget/credential_popup/login_credentials_popup.dart';
import 'prompt_sign_in.dart';

/// Connection-screen authentication, state-aware:
///   * No auth configured  -> just the auth-mode picker.
///   * Already signed in    -> "Signed in as the user" + Log out (no login form,
///                             so we never re-run a login the server rejects).
///   * Needs sign-in        -> inline username/password with Test + Sign in,
///                             the same shape as the first-run (FTUE) flow.
class InlineAuthSection extends HookConsumerWidget {
  const InlineAuthSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authType = ref.watch(authTypeKeyProvider) ?? AuthType.none;
    final needsReauth = ref.watch(needsReauthProvider);
    final storedUsername = ref.watch(authUsernameProvider);

    final signedIn =
        authType != AuthType.none &&
        ref.watch(hasStoredCredentialsProvider) &&
        !needsReauth;
    final showAccountCodes =
        authType == AuthType.uiLogin &&
        ref.watch(settledAccountAccessProvider).capability !=
            AccountCapability.unsupported;

    final username = useTextEditingController(text: storedUsername ?? '');
    final password = useTextEditingController();
    final busy = useState(false);
    final testing = useState(false);
    final message = useState<String?>(null);
    final isError = useState(false);

    // The server ROOT, not the API base: sign-in and the auth probe append
    // their own paths (`/login.html`, `api/graphql`), so an `/api/v1` here
    // posts Simple Login to `/api/v1/login.html` and 404s.
    String resolvedBaseUrl() => Endpoints.baseApi(
      baseUrl: ref.read(serverUrlProvider) ?? DBKeys.serverUrl.initial,
      port: ref.read(serverPortProvider),
      addPort: ref.read(serverPortToggleProvider).ifNull(),
      appendApiToUrl: false,
    );

    // Validate the entered credentials WITHOUT committing them.
    Future<void> testConnection() async {
      if (username.text.trim().isEmpty || password.text.isEmpty) {
        isError.value = true;
        message.value = context.l10n.onboardingCredsRejected;
        return;
      }
      testing.value = true;
      message.value = null;
      try {
        final result = await ref
            .read(authCoordinatorProvider.notifier)
            .testConnection(
              authType: authType,
              serverBaseUrl: resolvedBaseUrl(),
              username: username.text.trim(),
              password: password.text,
              makeGqlClient: () =>
                  ref.read(unauthenticatedGraphQlClientProvider),
            );
        if (!context.mounted) return;
        if (result is TestConnectionSuccess) {
          isError.value = false;
          message.value = context.l10n.authTestConnectionSuccess;
        } else if (result is TestConnectionFailure) {
          isError.value = true;
          message.value = authFailureText(context, result.kind);
        }
      } catch (e) {
        if (!context.mounted) return;
        isError.value = true;
        message.value = authFailureText(context, classifyAuthError(e).kind);
      } finally {
        if (context.mounted) testing.value = false;
      }
    }

    // Commit the credentials. On success the section flips to "Signed in".
    Future<void> signIn() async {
      if (username.text.trim().isEmpty || password.text.isEmpty) {
        isError.value = true;
        message.value = context.l10n.onboardingCredsRejected;
        return;
      }
      busy.value = true;
      message.value = null;
      try {
        await performSignIn(
          ref,
          authType: authType,
          serverBaseUrl: resolvedBaseUrl(),
          username: username.text.trim(),
          password: password.text,
        );
        if (!context.mounted) return;
        password.clear();
        isError.value = false;
        message.value = null;
        ref.read(toastProvider)?.show(context.l10n.authTestConnectionSuccess);
      } catch (e) {
        if (!context.mounted) return;
        isError.value = true;
        message.value = authFailureText(context, classifyAuthError(e).kind);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> openCodeDialog(AccountCodeMode mode) async {
      final redeem = ref.read(accountActionsProvider).redeemCode;
      await showDialog<void>(
        context: context,
        builder: (_) => AccountCodeDialog(mode: mode, onSubmit: redeem),
      );
    }

    Future<void> logout() async {
      final signOut = ref.read(accountActionsProvider).signOut;
      final current = ref
          .read(authCredentialsStoreProvider.notifier)
          .captureSession();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: Text(context.l10n.authLogout),
          content: Text(context.l10n.authLogoutConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(context.l10n.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text(context.l10n.authLogout),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted || !current()) return;
      await signOut();
      if (!context.mounted) return;
      password.clear();
      message.value = null;
    }

    Future<void> onAuthModeChanged(AuthType? next) async {
      if (next == null || next == authType) return;
      stayOnConnectionAfterIdentityChange();
      await ref.read(backgroundDownloadControllerProvider).changeIdentity(
        () async {
          if (next == AuthType.none) {
            final store = ref.read(authCredentialsStoreProvider.notifier);
            await store.clearUiLoginTokens();
            await store.clearSimpleLoginCookie();
            await store.clearBasicCredentials();
          }
          // No "Session expired" banner here. Nothing expired: the user just
          // picked a different mode and is standing on the sign-in fields, so
          // the banner only flashed across the top and then went away. A real
          // expiry still raises it from the request paths that meet the 401.
          ref.read(needsReauthProvider.notifier).set(false);
          ref.read(authTypeKeyProvider.notifier).update(next);
        },
      );
      if (!context.mounted) return;
      message.value = null;
      password.clear();
    }

    Padding pad(Widget child) =>
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: child);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: context.l10n.authentication),
        pad(
          // M3 DropdownMenu (not the legacy DropdownButtonFormField, whose menu
          // anchors the selected item over the field and can open upward, wider
          // than the field). Opens below, sized to the field. Keyed by authType
          // so it re-seeds when the auth mode is changed elsewhere (e.g. logout).
          DropdownMenu<AuthType>(
            key: ValueKey(authType),
            initialSelection: authType,
            expandedInsets: EdgeInsets.zero,
            requestFocusOnTap: false,
            label: Text(context.l10n.authType),
            leadingIcon: const Icon(Icons.security_rounded),
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
            ),
            dropdownMenuEntries: AuthType.values
                .map(
                  (t) =>
                      DropdownMenuEntry(value: t, label: t.toLocale(context)),
                )
                .toList(),
            onSelected: onAuthModeChanged,
          ),
        ),
        if (authType != AuthType.none) ...[
          if (signedIn) ...[
            ListTile(
              leading: Icon(
                Icons.check_circle_rounded,
                color: theme.colorScheme.primary,
              ),
              title: Text(context.l10n.connectionAuthSignedIn),
              subtitle: (storedUsername != null && storedUsername.isNotBlank)
                  ? Text(storedUsername)
                  : null,
            ),
            ListTile(
              leading: Icon(
                Icons.logout_rounded,
                color: theme.colorScheme.error,
              ),
              title: Text(
                context.l10n.authLogout,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: logout,
            ),
          ] else ...[
            if (needsReauth)
              pad(
                Text(
                  context.l10n.connectionAuthSignInNeeded,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            pad(
              TextField(
                controller: username,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: context.l10n.userName,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person_rounded),
                ),
              ),
            ),
            pad(
              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.password,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_rounded),
                ),
                onSubmitted: (_) => signIn(),
              ),
            ),
            if (showAccountCodes)
              pad(
                Wrap(
                  children: [
                    TextButton(
                      onPressed: busy.value || testing.value
                          ? null
                          : () => openCodeDialog(AccountCodeMode.registration),
                      child: Text(context.l10n.accountRegistrationTitle),
                    ),
                    TextButton(
                      onPressed: busy.value || testing.value
                          ? null
                          : () => openCodeDialog(AccountCodeMode.recovery),
                      child: Text(context.l10n.accountRecoveryTitle),
                    ),
                  ],
                ),
              ),
            if (message.value != null)
              pad(
                Text(
                  message.value!,
                  style: TextStyle(
                    color: isError.value
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
            pad(
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (busy.value || testing.value)
                          ? null
                          : testConnection,
                      icon: testing.value
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering_rounded),
                      label: Text(context.l10n.authTestConnection),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (busy.value || testing.value) ? null : signIn,
                      icon: busy.value
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded),
                      label: Text(context.l10n.onboardingSignIn),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}
