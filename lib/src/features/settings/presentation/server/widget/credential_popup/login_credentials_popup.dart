// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/endpoints.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../features/auth/data/auth_coordinator.dart';
import '../../../../../../features/auth/presentation/auth_failure_text.dart';
import '../../../../../../features/auth/presentation/sign_in_action.dart';
import '../../../../../../global_providers/global_providers.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../utils/platform/web_auth_mode.dart';
import '../../../../../../widgets/popup_widgets/pop_button.dart';
import '../../../../../account/data/account_actions.dart';
import '../../../../../account/data/account_providers.dart';
import '../../../../../account/data/server_account_capability.dart';
import '../../../../../account/domain/account_access.dart';
import '../../../../../account/presentation/account_code_dialog.dart';
import '../client/server_port_tile/server_port_tile.dart';
import '../client/server_url_tile/server_url_tile.dart';

part 'login_credentials_popup.g.dart';

@riverpod
class AuthUsername extends _$AuthUsername
    with SharedPreferenceClientMixin<String> {
  @override
  String? build() => initialize(DBKeys.authUsername);
}

class LoginCredentialsPopup extends HookConsumerWidget {
  const LoginCredentialsPopup({
    super.key,
    required this.authType,
    this.allowModeSelection = false,
  });

  final AuthType authType;
  final bool allowModeSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMode = useState(this.authType);
    final authType = selectedMode.value;
    final web = ref.watch(isWebProvider);
    final unsupported = web && isWebUnsupportedAuthMode(authType);
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final username = useTextEditingController(
      text: ref.read(authUsernameProvider) ?? '',
    );
    final password = useTextEditingController();
    final testing = useState(false);
    final testResult = useState<String?>(null);
    final testResultIsError = useState(false);
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
        (ref.watch(authTypeKeyProvider) != AuthType.uiLogin ||
            ref.watch(settledAccountAccessProvider).capability !=
                AccountCapability.unsupported) &&
        serverAccountCapability != AccountCapability.unsupported;

    Future<void> openCodeDialog(AccountCodeMode mode) async {
      final redeem = ref.read(accountActionsProvider).redeemCode;
      var completed = false;
      await showDialog<void>(
        context: context,
        builder: (_) => AccountCodeDialog(
          mode: mode,
          onSubmit: ({required code, username, required password}) async {
            await redeem(code: code, username: username, password: password);
            completed = true;
          },
        ),
        animationStyle: context.motionStyle,
      );
      if (completed && context.mounted) Navigator.pop(context);
    }

    Future<bool> confirmInsecureIfNeeded(String resolvedUrl) async {
      if (!resolvedUrl.startsWith('http://')) return true;
      if (isLocalAddress(resolvedUrl)) return true;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          icon: const Icon(FluentIcons.warning_24_regular),
          title: Text(context.l10n.authInsecureTransportTitle),
          content: Text(context.l10n.authInsecureTransportWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(context.l10n.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text(context.l10n.authInsecureTransportContinue),
            ),
          ],
        ),
        animationStyle: context.motionStyle,
      );
      return proceed == true;
    }

    String resolveBaseUrl() {
      final baseUrl = ref.read(serverUrlProvider) ?? DBKeys.serverUrl.initial;
      // Sign-in paths are appended to the server root.
      return Endpoints.baseApi(
        baseUrl: baseUrl,
        port: ref.read(serverPortProvider),
        addPort: ref.read(serverPortToggleProvider).ifNull(),
        appendApiToUrl: false,
      );
    }

    Future<void> doTest() async {
      if (!(formKey.currentState?.validate()).ifNull()) return;
      testing.value = true;
      testResult.value = null;
      try {
        final resolvedUrl = resolveBaseUrl();
        if (!await confirmInsecureIfNeeded(resolvedUrl)) {
          if (!context.mounted) return;
          testing.value = false;
          return;
        }
        final result = await ref
            .read(authCoordinatorProvider.notifier)
            .testConnection(
              authType: authType,
              serverBaseUrl: resolvedUrl,
              username: username.text,
              password: password.text,
              makeGqlClient: () =>
                  ref.read(unauthenticatedGraphQlClientProvider),
            );
        if (!context.mounted) return;
        if (result is TestConnectionSuccess) {
          testResult.value = context.l10n.authTestConnectionSuccess;
          testResultIsError.value = false;
        } else if (result is TestConnectionFailure) {
          testResultIsError.value = true;
          testResult.value = authFailureText(context, result.kind);
        }
      } finally {
        if (context.mounted) testing.value = false;
      }
    }

    Future<void> doSave() async {
      if (unsupported || testing.value) return;
      if (!(formKey.currentState?.validate()).ifNull()) return;
      testing.value = true;
      testResult.value = null;
      try {
        final resolvedUrl = resolveBaseUrl();
        if (!await confirmInsecureIfNeeded(resolvedUrl)) {
          if (!context.mounted) return;
          testing.value = false;
          return;
        }
        await performSignIn(
          ref,
          authType: authType,
                serverBaseUrl: resolvedUrl,
                username: username.text,
                password: password.text,
        );
        if (context.mounted) Navigator.pop(context);
      } catch (e) {
        if (!context.mounted) return;
        testResultIsError.value = true;
        testResult.value = authFailureText(context, classifyAuthError(e).kind);
      } finally {
        if (context.mounted) testing.value = false;
      }
    }

    return AlertDialog(
      scrollable: true,
      title: Text(context.l10n.credentials),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (allowModeSelection)
              DropdownButtonFormField<AuthType>(
                icon: const Icon(
                  FluentIcons.caret_down_24_filled,
                ),
                initialValue: authType,
                decoration: InputDecoration(
                  labelText: context.l10n.serverAuthMode,
                ),
                items: AuthType.values
                    .map(
                      (mode) => DropdownMenuItem(
                        value: mode,
                        enabled: !(web && isWebUnsupportedAuthMode(mode)),
                        child: Text(switch (mode) {
                          AuthType.none => context.l10n.serverAuthNone,
                          AuthType.basic => context.l10n.serverAuthBasic,
                          AuthType.simpleLogin => context.l10n.serverAuthSimple,
                          AuthType.uiLogin => context.l10n.serverAuthUi,
                        }),
                      ),
                    )
                    .toList(),
                onChanged: testing.value
                    ? null
                    : (mode) {
                        if (mode != null) selectedMode.value = mode;
                        testResult.value = null;
                      },
              ),
            if (authType != AuthType.none) ...[
            TextFormField(
              controller: username,
              validator: (v) => v.isBlank ? context.l10n.errorUserName : null,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: context.l10n.userName,
                border: const OutlineInputBorder(),
              ),
            ),
            const Gap(4),
            TextFormField(
              controller: password,
              validator: (v) => v.isBlank ? context.l10n.errorPassword : null,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                if (!testing.value) doSave();
              },
              decoration: InputDecoration(
                hintText: context.l10n.password,
                border: const OutlineInputBorder(),
              ),
            ),
            ],
            const Gap(12),
            Text(
              context.l10n.authReverseProxyHelp,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).hintColor,
              ),
            ),
            if (authType == AuthType.uiLogin) ...[
              const Gap(8),
              Text(
                context.l10n.authImageUrlLogWarning,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
            if (showAccountCodes)
              Wrap(
                children: [
                  TextButton(
                    onPressed: testing.value
                        ? null
                        : () => openCodeDialog(AccountCodeMode.registration),
                    child: Text(context.l10n.accountRegistrationTitle),
                  ),
                  TextButton(
                    onPressed: testing.value
                        ? null
                        : () => openCodeDialog(AccountCodeMode.recovery),
                    child: Text(context.l10n.accountRecoveryTitle),
                  ),
                ],
              ),
            if (testResult.value != null) ...[
              const Gap(8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: SelectableText(
                    testResult.value!,
                    style: TextStyle(
                      color: testResultIsError.value
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        const PopButton(),
        TextButton(
          onPressed: testing.value || unsupported || authType == AuthType.none
              ? null
              : doTest,
          child: testing.value
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.l10n.authTestConnection),
        ),
        ElevatedButton(
          onPressed: testing.value || unsupported ? null : doSave,
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}

/// Recognizes localhost, 127.x and RFC1918 IPv4 hosts that skip the insecure-HTTP warning.
@visibleForTesting
bool isLocalAddress(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase();
  if (host == null || host.isEmpty) return false;
  if (host == 'localhost') return true;
  final parts = host.split('.');
  if (parts.length != 4) return false;
  final octets = parts.map(int.tryParse).toList();
  if (octets.any((o) => o == null || o < 0 || o > 255)) return false;
  final a = octets[0]!;
  final b = octets[1]!;
  if (a == 127) return true; // 127.0.0.0/8
  if (a == 10) return true; // 10.0.0.0/8
  if (a == 192 && b == 168) return true; // 192.168.0.0/16
  if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
  return false;
}
