import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:graphql/client.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/network/graphql_errors.dart';
import '../data/account_actions.dart';

class AccountPasswordDialog extends HookWidget {
  const AccountPasswordDialog({super.key, required this.onSubmit});

  final Future<void> Function({
    required String currentPassword,
    required String newPassword,
  })
  onSubmit;

  @override
  Widget build(BuildContext context) {
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final password = useTextEditingController();
    final confirmation = useTextEditingController();
    final busy = useState(false);
    final error = useState<String?>(null);
    final currentPassword = useTextEditingController();
    final title = context.l10n.accountChangePassword;

    Future<void> submit() async {
      if (busy.value || !(formKey.currentState?.validate() ?? false)) return;
      busy.value = true;
      error.value = null;
      try {
        await onSubmit(
          currentPassword: currentPassword.text,
          newPassword: password.text,
        );
        if (context.mounted) Navigator.pop(context);
      } catch (failure) {
        if (!context.mounted) return;
        final cause = failure is OperationMessageException
            ? failure.exception
            : failure;
        final message = cause is OperationException
            ? OperationMessageException(cause).toString()
            : cause.toString();
        error.value = failure is AccountPasswordWhitespace
            ? context.l10n.accountPasswordWhitespace
            : failure is AccountPasswordUnconfirmed
            ? context.l10n.accountPasswordUnconfirmed
            : failure is AccountPasswordSignInRequired
            ? context.l10n.accountPasswordSignInRequired
            : isConnectionError(cause)
            ? context.l10n.authTestConnectionFailedNetwork
            : isPermissionDenied(cause)
            ? context.l10n.accountPermissionDenied
            : message.trim().isEmpty
            ? context.l10n.errorSomethingWentWrong
            : message;
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return PopScope(
      canPop: !busy.value,
      child: AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentPassword,
                enabled: !busy.value,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.l10n.accountCurrentPassword,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? context.l10n.errorPassword
                    : null,
              ),
              const Gap(8),
              TextFormField(
                controller: password,
                enabled: !busy.value,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.l10n.accountNewPassword,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? context.l10n.errorPassword
                    : null,
              ),
              const Gap(8),
              TextFormField(
                controller: confirmation,
                enabled: !busy.value,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.l10n.accountConfirmPassword,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? context.l10n.errorPassword
                    : value != password.text
                    ? context.l10n.accountPasswordsDoNotMatch
                    : null,
              ),
              const Gap(8),
              if (error.value != null)
                SelectableText(
                  error.value!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (busy.value) const LinearProgressIndicator(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy.value ? null : () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: busy.value ? null : submit,
            child: Text(title),
          ),
        ],
      ),
    );
  }
}
