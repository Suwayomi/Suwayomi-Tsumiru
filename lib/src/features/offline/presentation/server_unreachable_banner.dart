// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../data/server_reachability.dart';

// Inline placement avoids competing with the re-auth banner for ScaffoldMessenger.
class ServerUnreachableBanner extends ConsumerWidget {
  const ServerUnreachableBanner({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreachable = ref.watch(serverUnreachableProvider);
    // View offline persists after another request clears the outage flag; keep a route back online.
    final viewingOffline = ref.watch(viewOfflineNowProvider);
    if (!unreachable && !viewingOffline) return const SizedBox.shrink();

    void goOnline() {
      ref.read(viewOfflineNowProvider.notifier).set(false);
      ref.read(serverUnreachableProvider.notifier).set(false);
      onRetry?.call();
    }

    if (!unreachable) {
      return MaterialBanner(
        content: Text(context.l10n.offlineViewBannerTitle),
        leading: const Icon(FluentIcons.cloud_off_24_regular),
        actions: [
          TextButton(
            onPressed: goOnline,
            child: Text(context.l10n.offlineViewGoOnline),
          ),
        ],
      );
    }

    return MaterialBanner(
      content: Text(context.l10n.serverUnreachableTitle),
      leading: const Icon(FluentIcons.cloud_off_24_regular),
      actions: [
        TextButton(
          onPressed: () => const ConnectionRoute().push(context),
          child: Text(context.l10n.serverUnreachableAction),
        ),
        TextButton(onPressed: goOnline, child: Text(context.l10n.refresh)),
      ],
    );
  }
}
