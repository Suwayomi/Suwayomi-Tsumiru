import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/misc/toast/toast.dart';
import '../../../widgets/section_title.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../data/account_catalogue.dart';
import '../data/account_catalogue_providers.dart';
import 'offline_settings_format.dart';

class InactiveAccountCatalogueTiles extends ConsumerWidget {
  const InactiveAccountCatalogueTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogues = ref.watch(inactiveAccountCataloguesProvider);
    if (catalogues.isLoading) return const SizedBox.shrink();
    if (catalogues.hasError) {
      return ListTile(title: Text(context.l10n.accountCataloguesUnavailable));
    }
    final rows = catalogues.value ?? const <AccountCatalogue>[];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SectionTitle(title: context.l10n.accountInactiveCatalogues),
        for (final catalogue in rows)
          ListTile(
            title: Text(
              catalogue.isNonAccount
                  ? context.l10n.accountCatalogueWithoutLogin
                  : catalogue.username ??
                        context.l10n.accountCatalogueOwner(catalogue.owner),
            ),
            subtitle: Text(
              '${catalogue.address ?? context.l10n.accountCatalogueUnknownServer} · ${formatBytes(catalogue.bytes)}',
            ),
            trailing: IconButton(
              tooltip: context.l10n.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _remove(context, ref, catalogue),
            ),
          ),
      ],
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    AccountCatalogue catalogue,
  ) async {
    final auth = ref.read(authCredentialsStoreProvider.notifier);
    final current = auth.captureSession();
    final epoch = auth.sessionEpoch;
    final actions = ref.read(accountCatalogueActionsProvider);
    final toast = ref.read(toastProvider);
    final failure = context.l10n.accountCatalogueRemoveFailed;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.accountCatalogueRemoveTitle),
        content: Text(
          context.l10n.accountCatalogueRemoveConfirm(
            catalogue.isNonAccount
                ? context.l10n.accountCatalogueWithoutLogin
                : catalogue.username ??
                      context.l10n.accountCatalogueOwner(catalogue.owner),
            catalogue.address ?? context.l10n.accountCatalogueUnknownServer,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted || !current()) return;
    try {
      await actions.remove(catalogue, sessionEpoch: epoch);
    } catch (_) {
      if (context.mounted && current()) toast?.showError(failure);
    }
  }
}
