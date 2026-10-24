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
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../utils/platform/web_auth_mode.dart';
import '../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../account/data/account_actions.dart';
import '../../../account/data/account_providers.dart';
import '../../../account/data/server_account_capability.dart';
import '../../../account/domain/account_access.dart';
import '../../../account/presentation/account_code_dialog.dart';
import '../../../auth/data/auth_session_status.dart';
import '../../../auth/presentation/auth_failure_text.dart';
import '../../../offline/data/background/background_download_controller_shim.dart';
import '../../search/settings_search_registry.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
import '../server/widget/client/server_port_tile/server_port_tile.dart';
import '../server/widget/client/server_url_tile/server_url_tile.dart';
import '../server/widget/credential_popup/login_credentials_popup.dart';
import 'prompt_sign_in.dart';

class ConnectionAuthTypeTile extends ConsumerWidget {
  const ConnectionAuthTypeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authType = ref.watch(authTypeKeyProvider) ?? AuthType.none;
    final isWeb = ref.watch(isWebProvider);
    final authChoices = connectionAuthChoices(isWeb: isWeb);

    Future<void> onAuthModeChanged(AuthType next) async {
      if (next == authType) return;
      if (next != AuthType.none) {
        await showDialog<void>(
          context: context,
          builder: (_) => LoginCredentialsPopup(authType: next),
          animationStyle: context.motionStyle,
        );
        return;
      }
      stayOnConnectionAfterIdentityChange();
      await ref.read(backgroundDownloadControllerProvider).changeIdentity(
        () async {
          if (next == AuthType.none) {
            final store = ref.read(authCredentialsStoreProvider.notifier);
            await store.clearUiLoginTokens();
            await store.clearSimpleLoginCookie();
            await store.clearBasicCredentials();
          }
          // A deliberate mode change does not indicate session expiry.
          ref.read(needsReauthProvider.notifier).set(false);
          ref.read(authTypeKeyProvider.notifier).update(next);
        },
      );
    }

    return SettingsHighlightTarget(
      id: 'authentication',
      child: ListTile(
        title: Text(context.l10n.authType),
        subtitle: Text(authType.toLocale(context)),
        onTap: () => showDialog(
          context: context,
          builder: (dialogContext) => RadioListPopup<AuthType>(
            title: context.l10n.authType,
            optionList: authChoices,
            value: authType,
            getOptionTitle: (option) => option.toLocale(dialogContext),
            onChange: (option) {
              Navigator.pop(dialogContext);
              onAuthModeChanged(option);
            },
        ),
          animationStyle: context.motionStyle,
        ),
      ),
    );
  }
}

class ConnectionAuthWebHint extends ConsumerWidget {
  const ConnectionAuthWebHint({super.key, this.inCard = false});

  final bool inCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWeb = ref.watch(isWebProvider);
    if (!isWeb || ref.watch(webSameOriginProvider)) {
      return const SizedBox.shrink();
    }
    return Padding(
            padding: inCard
                ? const EdgeInsets.fromLTRB(16, 0, 16, 16)
                : const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              context.l10n.webUiLoginOnlyHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
    );
  }
}

class InlineAuthSection extends HookConsumerWidget {
  const InlineAuthSection({super.key, this.accountMode = false});

  /// Hides controls already shown by the Account card; shows only sign-in fields.
  final bool accountMode;

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
    final probeBaseUrl = Endpoints.baseApi(
      baseUrl: ref.watch(serverUrlProvider) ?? DBKeys.serverUrl.initial,
      port: ref.watch(serverPortProvider),
      addPort: ref.watch(serverPortToggleProvider).ifNull(),
      appendApiToUrl: false,
    );
    final serverAccountCapability = useServerAccountCapability(
      ref,
      probeBaseUrl,
      authType,
    );
    final showAccountCodes =
        authType == AuthType.uiLogin &&
        ref.watch(settledAccountAccessProvider).capability !=
            AccountCapability.unsupported &&
        serverAccountCapability != AccountCapability.unsupported;

    final username = useTextEditingController(text: storedUsername ?? '');
    final password = useTextEditingController();
    final busy = useState(false);
    final testing = useState(false);
    final message = useState<String?>(null);
    final isError = useState(false);

    // Use the server root: sign-in and probes append /login.html and api/graphql.
    String resolvedBaseUrl() => Endpoints.baseApi(
      baseUrl: ref.read(serverUrlProvider) ?? DBKeys.serverUrl.initial,
      port: ref.read(serverPortProvider),
      addPort: ref.read(serverPortToggleProvider).ifNull(),
      appendApiToUrl: false,
    );

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
        animationStyle: context.motionStyle,
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
        animationStyle: context.motionStyle,
      );
      if (confirmed != true || !context.mounted || !current()) return;
      await signOut();
      if (!context.mounted) return;
      password.clear();
      message.value = null;
    }

    useEffect(() {
      message.value = null;
      password.clear();
      return null;
    }, [authType]);

    if (accountMode && signedIn) return const SizedBox.shrink();

    Padding pad(Widget child) =>
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: child);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!accountMode) ...[
          SettingsGroupHeading(label: context.l10n.authentication),
          const SettingsGroupCard(children: [ConnectionAuthTypeTile()]),
          const ConnectionAuthWebHint(),
        ],
        if (authType != AuthType.none) ...[
          if (signedIn) ...[
            ListTile(
              title: Text(context.l10n.connectionAuthSignedIn),
              subtitle: (storedUsername != null && storedUsername.isNotBlank)
                  ? Text(storedUsername)
                  : null,
            ),
            ListTile(
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
