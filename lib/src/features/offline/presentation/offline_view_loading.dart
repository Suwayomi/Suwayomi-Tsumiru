// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../widgets/custom_circular_progress_indicator.dart';
import '../data/offline_repository.dart';
import '../data/server_reachability.dart';

/// Library loading state with a way out: while a fallback-capable read is
/// still waiting on its network window, a "View offline" button serves the
/// on-device catalog immediately instead of making the user sit out the wait.
/// Renders as the plain shimmer when there is no catalog to offer.
class OfflineViewLoading extends ConsumerWidget {
  const OfflineViewLoading({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasCatalog =
        ref.watch(offlineCatalogAvailableProvider).value ?? false;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Expanded(child: CenterSorayomiShimmerIndicator()),
        if (hasCatalog)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: TextButton.icon(
              icon: const Icon(Icons.cloud_off_rounded),
              label: Text(context.l10n.viewOffline),
              onPressed: () =>
                  ref.read(viewOfflineNowProvider.notifier).set(true),
            ),
          ),
      ],
    );
  }
}
