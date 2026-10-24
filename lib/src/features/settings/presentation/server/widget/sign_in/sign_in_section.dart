import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/enum.dart';
import '../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../utils/platform/web_auth_mode.dart';
import '../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../../../account/data/account_providers.dart';
import '../../../../../account/domain/account_access.dart';
import '../../../../search/settings_search_registry.dart';
import '../../../../widgets/settings_group_card/settings_group_card.dart';
import 'data/sign_in_actions.dart';
import 'data/sign_in_executor.dart';
import 'data/sign_in_repository.dart';
import 'data/sign_in_transition.dart';

final signInAccountsCapabilityProvider =
    FutureProvider.autoDispose<AccountCapability>(
      (ref) => ref.watch(accountRepositoryProvider).capability(),
    );

String signInModeLabel(BuildContext context, AuthType mode) => switch (mode) {
  AuthType.none => context.l10n.serverAuthNone,
  AuthType.basic => context.l10n.serverAuthBasic,
  AuthType.simpleLogin => context.l10n.serverAuthSimple,
  AuthType.uiLogin => context.l10n.serverAuthUi,
};

// Kotlin serializes days as hours (for example, PT1440H for 60 days).
Duration signInDuration(String value) {
  final match = RegExp(
    r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
  ).firstMatch(value);
  if (match == null) throw FormatException('Invalid server duration');
  return Duration(
    microseconds:
        (((int.parse(match[1] ?? '0') * 86400 +
                        int.parse(match[2] ?? '0') * 3600 +
                        int.parse(match[3] ?? '0') * 60) +
                    double.parse(match[4] ?? '0')) *
                1000000)
            .round(),
  );
}

bool signInAdmin({
  required bool accounts,
  required AuthType mode,
  required int? userId,
}) => !accounts || mode != AuthType.uiLogin || userId == 1;

class SignInSection extends ConsumerStatefulWidget {
  const SignInSection({super.key});

  @override
  ConsumerState<SignInSection> createState() => _SignInSectionState();
}

class _SignInSectionState extends ConsumerState<SignInSection> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(signInSettingsProvider);
    final accountCapability = ref.watch(signInAccountsCapabilityProvider);
    void retry() {
      ref.invalidate(signInSettingsProvider);
      ref.invalidate(signInAccountsCapabilityProvider);
    }

    if (settings.isLoading || accountCapability.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final capability = accountCapability.value;
    if (settings.hasError ||
        accountCapability.hasError ||
        capability == null ||
        capability == AccountCapability.unknown) {
      return Column(
        children: [
          Text(context.l10n.serverSignInUnknown),
          TextButton(onPressed: retry, child: Text(context.l10n.retry)),
        ],
      );
    }
    final data = settings.value;
    if (data == null) return const SizedBox.shrink();
    final before = signInValues(data);
    final accounts = capability == AccountCapability.supported;
    final admin = signInAdmin(
      accounts: accounts,
      mode: before.mode,
      userId: ref.watch(currentAccountProvider)?.id,
    );
    final web = ref.watch(isWebProvider);
    final canManage =
        !_saving &&
        ref
            .watch(settledAccountAccessProvider)
            .allows(Enum$UserPermission.MANAGE_SETTINGS);
    final l = context.l10n;

    String refusal(SignInRefusal reason) => switch (reason) {
      SignInRefusal.credentialsRequired => l.serverSignInCredentialsRequired,
      SignInRefusal.adminOnly => l.serverSignInAdminOnly,
      SignInRefusal.unsupportedWebMode => l.serverSignInWebMode,
      SignInRefusal.webCredentials => l.serverSignInWebCredentials,
      SignInRefusal.separateSaves => l.serverSignInSeparateSaves,
    };

    Future<void> save(SignInValues values) async {
      if (_saving) return;
      setState(() => _saving = true);
      try {
        var proposed = values;
        final originalDiff = proposed.difference(before);
        if (accounts &&
            !isWebUnsupportedAuthMode(proposed.mode) &&
            (originalDiff.credentials ||
                before.mode != AuthType.uiLogin &&
                    proposed.mode == AuthType.uiLogin)) {
          proposed = proposed.copyWith(
            username: proposed.username.trim(),
            password: proposed.password.trim(),
          );
        }
        final diff = proposed.difference(before);
        final decision = decideSignInTransition(
          accounts: accounts,
          currentMode: before.mode,
          finalMode: proposed.mode,
          diff: diff,
          admin: admin,
          web: web,
          hasCredentials:
              proposed.username.trim().isNotEmpty &&
              proposed.password.trim().isNotEmpty,
        );
        if (decision.refusal != null) {
          ref.read(toastProvider)?.show(refusal(decision.refusal!));
          return;
        }
        final actions = SignInActions(ref);
        await actions.preflight(
          accounts: accounts,
          before: before,
          proposed: proposed,
        );
        if (!context.mounted) return;
        if (proposed.mode != before.mode || diff.credentials || diff.audience) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(l.serverSignInConfirmTitle),
              content: Text(l.serverSignInConfirmBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(l.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(l.serverSignInChange),
                ),
              ],
            ),
            animationStyle: context.motionStyle,
          );
          if (confirmed != true || !context.mounted) return;
        }
        await actions.save(
          before: before,
          proposed: proposed,
          accounts: accounts,
          admin: admin,
          web: web,
        );
      } on SignInPreflightException catch (error) {
        if (!context.mounted) return;
        ref.read(toastProvider)?.show(switch (error.reason) {
          'credentials' => l.serverSignInCredentialsRequired,
          'permission' => l.serverSignInManageUsers,
          'taken' => l.serverSignInUsernameTaken,
          _ => l.serverSignInUnknown,
        });
      } catch (_) {
        if (mounted) ref.read(toastProvider)?.show(l.serverSignInUnknown);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }

    Widget target(String id, Widget child) => SettingsHighlightTarget(
      id: id,
      child: Semantics(container: true, explicitChildNodes: true, child: child),
    );
    Widget textRow(
      String id,
      String title,
      String value,
      SignInValues Function(String) update, {
      bool secret = false,
    }) => target(
      id,
      SettingsPropTile(
        title: title,
        subtitle: secret ? null : value,
        type: SettingsPropType.textField(
          value: value,
          canObscure: secret,
          onChanged: canManage ? (value) => save(update(value)) : null,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        SettingsGroupCard(
          children: [
            target(
              'serverAuthMode',
              ListTile(
                title: Text(l.serverAuthMode),
                subtitle: Text(signInModeLabel(context, before.mode)),
                onTap: canManage
                    ? () async {
                        final selected = await showDialog<AuthType>(
                          context: context,
                          builder: (dialogContext) => RadioListPopup<AuthType>(
                            title: l.serverAuthMode,
                            value: before.mode,
                            optionList: AuthType.values,
                            getOptionTitle: (mode) =>
                                signInModeLabel(context, mode),
                            isOptionEnabled: (mode) =>
                                mode == AuthType.none ||
                                (!(web && isWebUnsupportedAuthMode(mode)) &&
                                    !(accounts &&
                                        !admin &&
                                        isWebUnsupportedAuthMode(mode)) &&
                                    before.username.trim().isNotEmpty &&
                                    before.password.trim().isNotEmpty),
                            onChange: (mode) =>
                                Navigator.pop(dialogContext, mode),
                          ),
                          animationStyle: context.motionStyle,
                        );
                        if (selected != null &&
                            selected != before.mode &&
                            mounted) {
                          await save(before.copyWith(mode: selected));
                        }
                      }
                    : null,
              ),
            ),
            if (admin) ...[
              textRow(
                'serverAuthUsername',
                accounts ? l.serverAdminUsername : l.serverAuthUsername,
                before.username,
                (value) => before.copyWith(username: value),
              ),
              textRow(
                'serverAuthPassword',
                accounts ? l.serverAdminPassword : l.serverAuthPassword,
                before.password,
                (value) => before.copyWith(password: value),
                secret: true,
              ),
            ],
          ],
        ),
        if (before.mode == AuthType.uiLogin) ...[
          SettingsGroupHeading(label: l.serverAuthUi),
          SettingsGroupCard(
            children: [
              textRow(
                'serverJwtAudience',
                l.serverJwtAudience,
                before.audience,
                (value) => before.copyWith(audience: value),
              ),
              target(
                'serverAccessExpiry',
                SettingsPropTile(
                  title: l.serverAccessExpiry,
                  subtitle: l.serverSignInMinutes(
                    signInDuration(before.accessExpiry).inMinutes,
                  ),
                  type: SettingsPropType.numberPicker(
                    min: 1,
                    max: 240,
                    value: signInDuration(
                      before.accessExpiry,
                    ).inMinutes.clamp(1, 240),
                    onChanged: canManage
                        ? (value) =>
                              save(before.copyWith(accessExpiry: 'PT${value}M'))
                        : null,
                  ),
                ),
              ),
              target(
                'serverRefreshExpiry',
                SettingsPropTile(
                  title: l.serverRefreshExpiry,
                  subtitle: l.serverSignInDays(
                    signInDuration(before.refreshExpiry).inDays,
                  ),
                  type: SettingsPropType.numberPicker(
                    min: 1,
                    max: 365,
                    value: signInDuration(
                      before.refreshExpiry,
                    ).inDays.clamp(1, 365),
                    onChanged: canManage
                        ? (value) => save(
                            before.copyWith(refreshExpiry: 'PT${value * 24}H'),
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
