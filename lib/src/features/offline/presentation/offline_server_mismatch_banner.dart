// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../data/offline_download_providers.dart';
import '../data/offline_repository.dart';

class OfflineServerMismatchBanner extends ConsumerWidget {
  const OfflineServerMismatchBanner({
    super.key,
    this.showAfterDismissal = false,
  });

  final bool showAfterDismissal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mismatch = ref.watch(offlineServerMismatchProvider).value;
    if (mismatch == null || (mismatch.dismissed && !showAfterDismissal)) {
      return const SizedBox.shrink();
    }

    return MaterialBanner(
      content: Text(
        mismatch.dismissed
            ? context.l10n.offlineServerMismatchDisabled
            : context.l10n.offlineServerMismatch,
      ),
      leading: const Icon(Icons.dns_rounded),
      actions: [
        if (!mismatch.dismissed)
          TextButton(
            onPressed: () => dismissOfflineServerMismatch(ref, mismatch),
            child: Text(context.l10n.offlineServerMismatchDismiss),
          ),
        TextButton(
          onPressed: () => _confirmClear(context, ref),
          child: Text(
            mismatch.dismissed
                ? context.l10n.offlineServerMismatchClearAction
                : context.l10n.offlineServerMismatchClear,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.offlineServerMismatchConfirmTitle),
        content: Text(context.l10n.offlineServerMismatchConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.offlineServerMismatchClearAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await clearOfflineCatalog(ref);
    ref.invalidate(offlineServerMismatchProvider);
  }
}
