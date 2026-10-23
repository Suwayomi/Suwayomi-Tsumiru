// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/enum.dart';
import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../account/data/account_actions.dart';
import '../../../account/data/account_providers.dart';
import '../../../account/domain/account_access.dart';
import '../../../account/presentation/account_password_dialog.dart';
import '../../../account/presentation/account_permission_labels.dart';
import '../../../account/presentation/sign_out_action.dart';
import '../../../auth/data/auth_session_status.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
import '../server/widget/credential_popup/login_credentials_popup.dart';
import 'inline_auth_section.dart';

/// The Account block of the Connection page, shown on servers with user
/// accounts: the Account card (the Account screen's rows, minus Manage users
/// which moved to the Server hub), the sign-in fields while signed out, and
/// the Sign out / Sign in card.
class ConnectionAccountSection extends ConsumerWidget {
  const ConnectionAccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(currentAccountProvider);
    final hasCredentials = ref.watch(hasStoredCredentialsProvider);
    final access = ref.watch(settledAccountAccessProvider);
    final verified = access.capability == AccountCapability.supported;
    final actions = ref.read(accountActionsProvider);

    final permissions = accountPermissionLabels(context);
    final canChangePassword =
        verified &&
        (account?.id != 1 ||
            access.allows(Enum$UserPermission.MANAGE_SETTINGS));
    final allowedCount = permissions.keys.where(access.allows).length;
    final roles = account?.roles
        .map(
          (role) => switch (role) {
            Enum$UserRole.ADMIN => context.l10n.accountRoleAdmin,
            Enum$UserRole.USER => context.l10n.accountRoleUser,
            Enum$UserRole.VISITOR => context.l10n.accountRoleVisitor,
            Enum$UserRole.$unknown => context.l10n.accountRoleUnknown,
          },
        )
        .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroupHeading(label: context.l10n.accountTitle),
        SettingsGroupCard(
          children: [
            if (hasCredentials && !verified)
              ListTile(subtitle: Text(context.l10n.accountSettingsUnavailable)),
            if (hasCredentials && account != null) ...[
              ListTile(
                title: Text(account.username),
                subtitle: Text(roles ?? context.l10n.accountRoleUnknown),
              ),
              ListTile(
                title: Text(context.l10n.accountChangePassword),
                enabled: canChangePassword,
                onTap: !canChangePassword
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) => AccountPasswordDialog(
                          onSubmit: actions.changePassword,
                        ),
                        animationStyle: context.motionStyle,
                      ),
              ),
              ExpansionTile(
                title: Text(context.l10n.accountPermissions),
                subtitle: Text(
                  !verified
                      ? context.l10n.accountPermissionsUnavailable
                      : allowedCount == permissions.length
                      ? context.l10n.accountPermissionsFullAccess
                      : context.l10n.accountPermissionsSummary(
                          allowedCount,
                          permissions.length,
                        ),
                ),
                children: [
                  for (final entry in permissions.entries)
                    ListTile(
                      dense: true,
                      title: Text(entry.value),
                      trailing: Text(
                        !verified
                            ? context.l10n.accountPermissionsUnavailable
                            : access.allows(entry.key)
                            ? context.l10n.accountPermissionAllowed
                            : context.l10n.accountPermissionRestricted,
                      ),
                    ),
                ],
              ),
            ],
            const ConnectionAuthTypePicker(inCard: true),
          ],
        ),
        const InlineAuthSection(accountMode: true),
        const SizedBox(height: 16),
        SettingsGroupCard(
          children: [
            if (hasCredentials)
              ListTile(
                title: Text(
                  context.l10n.accountSignOut,
                  style: TextStyle(color: context.theme.colorScheme.error),
                ),
                onTap: () => confirmAndSignOutAccount(context, ref),
              )
            else
              ListTile(
                title: Text(context.l10n.onboardingSignIn),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      const LoginCredentialsPopup(authType: AuthType.uiLogin),
                  animationStyle: context.motionStyle,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
