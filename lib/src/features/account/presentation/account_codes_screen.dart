import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/misc/app_utils.dart';
import '../../../utils/misc/toast/toast.dart';
import '../data/account_administration.dart';
import '../data/account_providers.dart';

String accountCodeExpiry(BuildContext context, String seconds) =>
    context.l10n.accountCodeExpires(
      DateFormat.yMd().add_jm().format(
        DateTime.fromMillisecondsSinceEpoch(
          int.parse(seconds) * 1000,
        ).toLocal(),
      ),
    );

Future<void> issueAccountCode(
  BuildContext context,
  WidgetRef ref, {
  int? userId,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => IssuedAccountCodeDialog(userId: userId),
  );
  if (context.mounted) ref.invalidate(accountCodesProvider);
}

class IssuedAccountCodeDialog extends HookConsumerWidget {
  const IssuedAccountCodeDialog({super.key, this.userId});
  final int? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admitted = ref.watch(settledAccountAccessProvider).canManageUsers;
    final future = useMemoized(() async {
      final repository = ref.read(accountRepositoryProvider);
      if (userId == null) {
        final result = await repository.createRegistrationCode(
          Input$CreateRegistrationCodeInput(),
        );
        if (result == null) {
          throw StateError('Missing registration code response');
        }
        return (code: result.code, expiresAt: result.expiresAt);
      }
      final result = await repository.createRecoveryCode(
        Input$CreateRecoveryCodeInput(userId: userId!),
      );
      if (result == null) throw StateError('Missing recovery code response');
      return (code: result.code, expiresAt: result.expiresAt);
    });
    final result = useFuture(future);
    final busy = result.connectionState != ConnectionState.done;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(
          userId == null
              ? context.l10n.accountRegistrationCode
              : context.l10n.accountRecoveryCode,
        ),
        content: !admitted
            ? Text(context.l10n.accountSettingsUnavailable)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy) const LinearProgressIndicator(),
                  if (result.hasError) Text(result.error.toString()),
                  if (result.hasData) ...[
                    Text(context.l10n.accountCodeShownOnce),
                    SelectableText(result.data!.code),
                    Text(accountCodeExpiry(context, result.data!.expiresAt)),
                  ],
                ],
              ),
        actions: [
          if (admitted && result.hasData)
            TextButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: result.data!.code)),
              child: Text(context.l10n.copyToClipboard),
            ),
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }
}

class AccountCodesScreen extends HookConsumerWidget {
  const AccountCodesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admitted = ref.watch(settledAccountAccessProvider).canManageUsers;
    final busy = useState(false);
    final codes = admitted ? ref.watch(accountCodesProvider) : null;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.accountCodes)),
      body: !admitted
          ? Center(child: Text(context.l10n.accountSettingsUnavailable))
          : Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.add_rounded),
                  title: Text(context.l10n.accountIssueRegistrationCode),
                  onTap: busy.value
                      ? null
                      : () => issueAccountCode(context, ref),
                ),
                if (busy.value) const LinearProgressIndicator(),
                Expanded(
                  child: codes!.showUiWhenData(
                    context,
                    (data) => ListView(
                      children: [
                        if (data.isEmpty)
                          ListTile(title: Text(context.l10n.accountNoCodes)),
                        for (final code in data)
                          ListTile(
                            title: Text(
                              code.purpose == Enum$UserCodePurpose.RECOVERY
                                  ? context.l10n.accountRecoveryCode
                                  : context.l10n.accountRegistrationCode,
                            ),
                            subtitle: Text(
                              [
                                if (code.user != null) code.user!.username,
                                accountCodeExpiry(context, code.expiresAt),
                              ].join('\n'),
                            ),
                            trailing: TextButton(
                              onPressed: busy.value
                                  ? null
                                  : () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text(
                                            context.l10n.accountRevokeCode,
                                          ),
                                          content: Text(
                                            context
                                                .l10n
                                                .accountRevokeCodeConfirmation,
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: Text(context.l10n.cancel),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: Text(
                                                context.l10n.accountRevokeCode,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed != true ||
                                          !context.mounted) {
                                        return;
                                      }
                                      busy.value = true;
                                      try {
                                        await AppUtils.guard(
                                          () => ref
                                              .read(accountRepositoryProvider)
                                              .revokeCode(
                                                Input$RevokeUserCodeInput(
                                                  id: code.id,
                                                ),
                                              ),
                                          ref.read(toastProvider),
                                        );
                                        if (context.mounted) {
                                          ref.invalidate(accountCodesProvider);
                                        }
                                      } finally {
                                        if (context.mounted) busy.value = false;
                                      }
                                    },
                              child: Text(context.l10n.accountRevokeCode),
                            ),
                          ),
                      ],
                    ),
                    refresh: () => ref.invalidate(accountCodesProvider),
                  ),
                ),
              ],
            ),
    );
  }
}
