// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../features/offline/data/offline_repository.dart';
import '../features/offline/data/server_reachability.dart';
import '../routes/router_config.dart';
import '../utils/extensions/custom_extensions.dart';
import 'emoticons.dart';

/// Shown when a request failed because the server couldn't be reached (wrong
/// URL, server down, no network) — as opposed to an auth or server-side error.
///
/// It points straight at Connection settings, the one screen where a wrong
/// server URL is fixed, so a disconnected user is never stranded on a blank
/// screen with no way forward.
class ServerUnreachableView extends ConsumerWidget {
  const ServerUnreachableView({super.key, this.onRetry, this.offlineEscape = false});

  /// Optional retry (re-runs the failed query). Omitted where there's nothing
  /// to re-fetch.
  final VoidCallback? onRetry;

  /// Offer the "View offline" pin. Only screens that honor the pin (the
  /// library) pass true; elsewhere the button would silently flip a switch
  /// the current screen ignores.
  final bool offlineEscape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The escape hatch belongs here as much as on the loading screen — a retry
    // that fails lands on this view, and without it the user is stuck waiting
    // out network windows with a perfectly good catalog on disk.
    final hasCatalog =
        ref.watch(offlineCatalogAvailableProvider).value ?? false;
    return Emoticons(
      iconData: Icons.cloud_off_rounded,
      title: context.l10n.serverUnreachableTitle,
      subTitle: context.l10n.serverUnreachableSubtitle,
      button: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: () => const ConnectionRoute().push(context),
            icon: const Icon(Icons.settings_ethernet_rounded),
            label: Text(context.l10n.serverUnreachableAction),
          ),
          if (offlineEscape && hasCatalog)
            TextButton.icon(
              icon: const Icon(Icons.cloud_off_rounded),
              label: Text(context.l10n.viewOffline),
              onPressed: () =>
                  ref.read(viewOfflineNowProvider.notifier).set(true),
            ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(context.l10n.refresh)),
        ],
      ),
    );
  }
}
