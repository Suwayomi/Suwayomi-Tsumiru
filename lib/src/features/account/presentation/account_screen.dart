import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/enum.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/misc/app_utils.dart';
import '../../../utils/misc/toast/toast.dart';
import '../../../widgets/popup_widgets/pop_button.dart';
import '../../auth/data/auth_session_status.dart';
import '../../settings/presentation/server/widget/credential_popup/login_credentials_popup.dart';
import '../data/account_actions.dart';
import '../data/account_providers.dart';
import '../domain/account_access.dart';
import 'account_password_dialog.dart';
import 'account_permission_labels.dart';

class AccountScreen extends HookConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(currentAccountProvider);
    final hasCredentials = ref.watch(hasStoredCredentialsProvider);
    final access = ref.watch(settledAccountAccessProvider);
    final verified = access.capability == AccountCapability.supported;
    final busy = useState(false);
    final actions = ref.read(accountActionsProvider);
    final toast = ref.read(toastProvider);

    Future<void> refresh() async {
      if (busy.value || !hasCredentials) return;
      busy.value = true;
      try {
        await AppUtils.guard(actions.refreshAccount, toast);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> signOut() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.accountSignOut),
          content: Text(context.l10n.accountSignOutConfirmation),
          actions: [
            const PopButton(),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.accountSignOut),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      busy.value = true;
      try {
        await AppUtils.guard(actions.signOut, toast);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    final permissions = accountPermissionLabels(context);
    final canChangePassword =
        verified &&
        !busy.value &&
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

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.accountTitle),
        actions: [
          IconButton(
            tooltip: context.l10n.refresh,
            onPressed: busy.value || !hasCredentials ? null : refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (busy.value) const LinearProgressIndicator(),
            if (!hasCredentials)
              ListTile(
                leading: const Icon(Icons.login_rounded),
                title: Text(context.l10n.onboardingSignIn),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      const LoginCredentialsPopup(authType: AuthType.uiLogin),
                ),
              ),
            if (hasCredentials && !verified)
              ListTile(subtitle: Text(context.l10n.accountSettingsUnavailable)),
            if (hasCredentials)
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: Text(context.l10n.accountSignOut),
                enabled: !busy.value,
                onTap: busy.value ? null : signOut,
              ),
            if (hasCredentials && account != null) ...[
              ListTile(
                leading: const Icon(Icons.person_rounded),
                title: Text(account.username),
                subtitle: Text(roles ?? context.l10n.accountRoleUnknown),
              ),
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: Text(context.l10n.accountChangePassword),
                enabled: canChangePassword,
                onTap: !canChangePassword
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) => AccountPasswordDialog(
                          onSubmit: actions.changePassword,
                        ),
                      ),
              ),
              if (access.canManageUsers)
                ListTile(
                  leading: const Icon(Icons.manage_accounts_rounded),
                  title: Text(context.l10n.accountPermissionManageUsers),
                  onTap: () => const ManageUsersRoute().push(context),
                ),
              const Divider(),
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
          ],
        ),
      ),
    );
  }
}
