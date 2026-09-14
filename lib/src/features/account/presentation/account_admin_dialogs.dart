import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/network/graphql_errors.dart';
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
    return AccountAdminForm(
      title: context.l10n.accountCreateUser,
      onSubmit: () => ref
          .read(accountRepositoryProvider)
          .register(
            Input$RegisterInput(
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
    return AccountAdminForm(
      title: user.username,
      onSubmit: immutable
          ? null
          : () async {
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
        for (final entry in accountPermissionLabels(context).entries)
          SwitchListTile(
            dense: true,
            title: Text(entry.value),
            value: permissions.value.contains(entry.key),
            onChanged: immutable
                ? null
                : (allowed) {
                    final updated = {...permissions.value};
                    if (allowed) {
                      updated.add(entry.key);
                    } else {
                      updated.remove(entry.key);
                    }
                    permissions.value = updated;
                  },
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
  });
  final String title;
  final List<Widget> children;
  final Future<void> Function()? onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = useMemoized(() => GlobalKey<FormState>());
    final busy = useState(false);
    final error = useState<String?>(null);
    final admitted = ref.watch(settledAccountAccessProvider).canManageUsers;
    Future<void> submit() async {
      if (busy.value || !admitted || !(key.currentState?.validate() ?? false)) {
        return;
      }
      busy.value = true;
      error.value = null;
      try {
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
              onPressed: admitted && !busy.value ? submit : null,
              child: Text(context.l10n.save),
            ),
        ],
      ),
    );
  }
}
