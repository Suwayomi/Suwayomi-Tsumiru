import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/network/graphql_errors.dart';
import '../../../widgets/popup_widgets/confirm_action.dart';
import '../data/account_administration.dart';
import '../data/account_providers.dart';
import '../data/graphql/__generated__/account.graphql.dart';
import 'account_codes_screen.dart';
import 'account_permission_labels.dart';

class CreateAccountDialog extends HookConsumerWidget {
  const CreateAccountDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = useTextEditingController();
    final password = useTextEditingController();
    final confirmation = useTextEditingController();
    final capability = ref.watch(accountCreationPermissionsProvider).value;
    final permissions = useState<Set<Enum$UserPermission>?>(null);
    return AccountAdminForm(
      title: context.l10n.accountCreateUser,
      onSubmit: () => ref
          .read(accountRepositoryProvider)
          .register(
            capability?.user == true && permissions.value != null
                ? Input$RegisterInput(
                    username: username.text.trim(),
                    password: password.text,
                    userPermissions: permissions.value!.toList(),
                  )
                : Input$RegisterInput(
                    username: username.text.trim(),
                    password: password.text,
                  ),
          ),
      children: [
        TextFormField(
          controller: username,
          autocorrect: false,
          decoration: InputDecoration(labelText: context.l10n.userName),
          validator: (value) => value == null || value.trim().isEmpty
              ? context.l10n.errorUserName
              : null,
        ),
        TextFormField(
          controller: password,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: context.l10n.password),
          validator: (value) => value == null || value.isEmpty
              ? context.l10n.errorPassword
              : null,
        ),
        TextFormField(
          controller: confirmation,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: context.l10n.accountConfirmPassword,
          ),
          validator: (value) => value != password.text
              ? context.l10n.accountPasswordsDoNotMatch
              : null,
        ),
        if (capability?.user == true)
          AccountPermissionPicker(
            permissions: permissions.value ?? defaultAccountPermissions,
            onChanged: (value) => permissions.value = value,
          ),
      ],
    );
  }
}

class EditAccountDialog extends HookConsumerWidget {
  const EditAccountDialog({super.key, required this.user});
  final Fragment$AccountDto user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(settledAccountAccessProvider);
    final permissions = useState(user.permissions.toSet());
    final role = useState(
      user.roles.contains(Enum$UserRole.ADMIN)
          ? Enum$UserRole.ADMIN
          : Enum$UserRole.USER,
    );
    final immutable = user.id == 1;
    final wasAdmin = user.roles.contains(Enum$UserRole.ADMIN);
    final isAdmin = access.canEditRoles
        ? role.value == Enum$UserRole.ADMIN
        : wasAdmin;
    final canManage =
        isAdmin ||
        permissions.value.contains(Enum$UserPermission.MANAGE_USERS);
    final losesAccess = (wasAdmin && !isAdmin) ||
        (user.permissions.contains(Enum$UserPermission.MANAGE_USERS) &&
            !permissions.value.contains(Enum$UserPermission.MANAGE_USERS));
    final users = !immutable && !canManage
        ? ref.watch(accountManagementUsersProvider)
        : null;
    bool hasOtherManager(List<Fragment$AccountDto> users) => users.any(
      (other) => other.id != user.id &&
          (other.roles.contains(Enum$UserRole.ADMIN) ||
              other.permissions.contains(Enum$UserPermission.MANAGE_USERS)),
    );
    final blocked =
        !immutable && !canManage &&
        (users?.hasError == true ||
            users?.isLoading != false ||
            !hasOtherManager(users?.value ?? []));
    final blockMessage = users?.hasError == true
        ? context.l10n.accountAdminCheckFailed
        : users?.isLoading == true
        ? context.l10n.accountAdminCheckLoading
        : context.l10n.accountLastManagerRequired;
    return AccountAdminForm(
      title: user.username,
      confirmSubmit: access.user?.id == user.id && losesAccess
          ? () => confirmAction(
              context,
              title: context.l10n.confirmRemoveOwnAdminTitle,
              message: context.l10n.confirmRemoveOwnAdminMessage,
              action: context.l10n.save,
            )
          : null,
      submitEnabled: !blocked,
      onSubmit: immutable
          ? null
          : () async {
              if (!canManage) {
                final List<Fragment$AccountDto> latest;
                try {
                  latest = await ref.refresh(
                    accountManagementUsersProvider.future,
                  );
                } catch (_) {
                  if (!context.mounted) return;
                  throw StateError(context.l10n.accountAdminCheckFailed);
                }
                if (!context.mounted) return;
                if (!hasOtherManager(latest)) {
                  throw StateError(context.l10n.accountLastManagerRequired);
                }
              }
              final updated = await ref
                  .read(accountRepositoryProvider)
                  .updateAccount(
                    accountPermissionUpdate(
                      userId: user.id,
                      permissions: permissions.value.toList(),
                      canEditRoles: ref
                          .read(settledAccountAccessProvider)
                          .canEditRoles,
                      role: role.value,
                    ),
                  );
              if (updated == null) {
                throw StateError('Missing updated user response');
              }
              if (ref.read(settledAccountAccessProvider).user?.id == user.id) {
                ref.invalidate(accountAccessProvider);
              }
            },
      children: [
        if (immutable) Text(context.l10n.accountBuiltInReadOnly),
        if (blocked) Text(blockMessage),
        if (access.canEditRoles)
          DropdownButtonFormField<Enum$UserRole>(
            initialValue: role.value,
            decoration: InputDecoration(labelText: context.l10n.accountRole),
            items: [
              DropdownMenuItem(
                value: Enum$UserRole.USER,
                child: Text(context.l10n.accountRoleUser),
              ),
              DropdownMenuItem(
                value: Enum$UserRole.ADMIN,
                child: Text(context.l10n.accountRoleAdmin),
              ),
            ],
            onChanged: immutable
                ? null
                : (value) {
                    if (value != null) role.value = value;
                  },
          ),
        AccountPermissionPicker(
          permissions: permissions.value,
          onChanged: immutable ? null : (value) => permissions.value = value,
        ),
        if (!immutable)
          TextButton(
            onPressed: () => issueAccountCode(context, ref, userId: user.id),
            child: Text(context.l10n.accountIssueRecoveryCode),
          ),
      ],
    );
  }
}

class AccountAdminForm extends HookConsumerWidget {
  const AccountAdminForm({
    super.key,
    required this.title,
    required this.children,
    this.onSubmit,
    this.confirmSubmit,
    this.submitEnabled = true,
  });
  final String title;
  final List<Widget> children;
  final Future<void> Function()? onSubmit;
  final Future<bool> Function()? confirmSubmit;
  final bool submitEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = useMemoized(() => GlobalKey<FormState>());
    final busy = useState(false);
    final error = useState<String?>(null);
    final admitted = ref.watch(settledAccountAccessProvider).canManageUsers;
    Future<void> submit() async {
      if (busy.value ||
          !admitted ||
          !submitEnabled ||
          !(key.currentState?.validate() ?? false)) {
        return;
      }
      busy.value = true;
      error.value = null;
      try {
        if (confirmSubmit != null && !await confirmSubmit!()) return;
        await onSubmit!();
        if (context.mounted) Navigator.pop(context);
      } catch (failure) {
        if (context.mounted) {
          final cause = failure is OperationMessageException
              ? failure.exception
              : failure;
          error.value = isPermissionDenied(cause)
              ? context.l10n.accountPermissionDenied
              : isConnectionError(cause)
              ? context.l10n.authTestConnectionFailedNetwork
              : failure.toString();
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return PopScope(
      canPop: !busy.value,
      child: AlertDialog(
        scrollable: true,
        title: Text(title),
        content: !admitted
            ? Text(context.l10n.accountSettingsUnavailable)
            : Form(
                key: key,
                child: AbsorbPointer(
                  absorbing: busy.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...children,
                      if (error.value != null)
                        SelectableText(
                          error.value!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (busy.value) const LinearProgressIndicator(),
                    ],
                  ),
                ),
              ),
        actions: [
          TextButton(
            onPressed: busy.value ? null : () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          if (onSubmit != null)
            ElevatedButton(
              onPressed: admitted && !busy.value && submitEnabled ? submit : null,
              child: Text(context.l10n.save),
            ),
        ],
      ),
    );
  }
}
