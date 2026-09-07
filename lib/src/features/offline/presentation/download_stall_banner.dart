import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../data/background/background_download_controller_shim.dart';
import '../data/offline_download_stall.dart';

class DownloadStallBanner extends ConsumerWidget {
  const DownloadStallBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reason = ref.watch(effectiveDownloadStallProvider);
    if (reason == null) return const SizedBox.shrink();
    return MaterialBanner(
      content: Text(switch (reason) {
        'wifi' => context.l10n.notificationDownloadsPausedWifi,
        'connection' => context.l10n.notificationDownloadsPausedNoServer,
        'budget' => context.l10n.notificationDownloadsPausedBudget,
        'background' => context.l10n.notificationDownloadsPausedBackground,
        _ => context.l10n.notificationDownloadsPausedService,
      }),
      leading: const Icon(Icons.cloud_off_rounded),
      actions: [
        TextButton(
          onPressed: () => ref
              .read(backgroundDownloadControllerProvider)
              .requestStart(userInitiated: true),
          child: Text(context.l10n.retry),
        ),
      ],
    );
  }
}
