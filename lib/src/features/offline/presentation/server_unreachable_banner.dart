// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../data/server_reachability.dart';

/// Inline banner shown while the server can't be reached, on the screens whose
/// content silently goes stale without it — the library, and a series page
/// where a download can sit at the same number for minutes with no explanation.
///
/// Deliberately NOT on the reader: that screen belongs to the page.
///
/// It sits inline (not via `ScaffoldMessenger`) so it never contends with the
/// app-wide re-auth banner for the shared banner slot.
class ServerUnreachableBanner extends ConsumerWidget {
  const ServerUnreachableBanner({super.key, this.onRetry});

  /// What the host screen re-fetches when the user retries. The offline pins
  /// are dropped either way; without this the banner could only ever refresh
  /// the library.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreachable = ref.watch(serverUnreachableProvider);
    // The "View offline" choice outlives the outage flag: any successful
    // request anywhere clears serverUnreachable while the catalog stays
    // pinned. Without its own banner that left no visible way back online.
    final viewingOffline = ref.watch(viewOfflineNowProvider);
    if (!unreachable && !viewingOffline) return const SizedBox.shrink();

    // Same contract as the library's refresh gestures: drop both pins, then
    // genuinely re-ask the server.
    void goOnline() {
      ref.read(viewOfflineNowProvider.notifier).set(false);
      ref.read(serverUnreachableProvider.notifier).set(false);
      onRetry?.call();
    }

    if (!unreachable) {
      return MaterialBanner(
        content: Text(context.l10n.offlineViewBannerTitle),
        leading: const Icon(Icons.cloud_off_rounded),
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
      leading: const Icon(Icons.cloud_off_rounded),
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
