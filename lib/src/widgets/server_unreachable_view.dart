// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../constants/db_keys.dart';
import '../features/offline/data/offline_repository.dart';
import '../features/offline/data/server_reachability.dart';
import '../global_providers/global_providers.dart';
import '../routes/router_config.dart';
import '../utils/extensions/custom_extensions.dart';
import '../utils/platform/web_auth_mode.dart';
import 'emoticons.dart';

final webAuthBlockedProvider = Provider<bool>(
  (ref) =>
      ref.watch(isWebProvider) &&
      !ref.watch(webSameOriginProvider) &&
      isWebUnsupportedAuthMode(
        ref.watch(authTypeKeyProvider) ?? DBKeys.authType.initial,
      ),
);

/// Shown when a request failed because the server couldn't be reached (wrong
/// URL, server down, no network) — as opposed to an auth or server-side error.
///
/// It points straight at Connection settings, the one screen where a wrong
/// server URL is fixed, so a disconnected user is never stranded on a blank
/// screen with no way forward.
class ServerUnreachableView extends ConsumerWidget {
  const ServerUnreachableView({
    super.key,
    this.onRetry,
    this.offlineEscape = false,
    this.webNotFoundVerdict = false,
  });

  /// Optional retry (re-runs the failed query). Omitted where there's nothing
  /// to re-fetch.
  final VoidCallback? onRetry;

  /// Offer the "View offline" pin. Only screens that honor the pin (the
  /// library) pass true; elsewhere the button would silently flip a switch
  /// the current screen ignores.
  final bool offlineEscape;

  final bool webNotFoundVerdict;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Gated here, not inside the button: a shrunk child still costs the
    // Column's spacing, doubling the gap between its neighbours.
    final hasCatalog =
        ref.watch(offlineCatalogAvailableProvider).value ?? false;
    final webAuthBlocked = ref.watch(webAuthBlockedProvider);
    final isWeb = ref.watch(isWebProvider);
    return Emoticons(
      iconData: Icons.cloud_off_rounded,
      title: context.l10n.serverUnreachableTitle,
      subTitle: webNotFoundVerdict && isWeb
          ? context.l10n.webServerAuthUnconfirmed
          : webAuthBlocked
          ? context.l10n.webUnsupportedAuthMode
          : context.l10n.serverUnreachableSubtitle,
      button: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: () => const ConnectionRoute().push(context),
            icon: const Icon(Icons.settings_ethernet_rounded),
            label: Text(context.l10n.serverUnreachableAction),
          ),
          if (offlineEscape && hasCatalog) const ViewOfflineButton(),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(context.l10n.refresh)),
        ],
      ),
    );
  }
}

/// The "View offline" pin. The error it accompanies stays visible — this is
/// the user's bypass, never an automatic mask. Self-gates on the catalog for
/// callers without a ref; ref-having parents should gate externally so a
/// shrunk child doesn't eat Column spacing.
class ViewOfflineButton extends ConsumerWidget {
  const ViewOfflineButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasCatalog =
        ref.watch(offlineCatalogAvailableProvider).value ?? false;
    if (!hasCatalog) return const SizedBox.shrink();
    return TextButton.icon(
      icon: const Icon(Icons.cloud_off_rounded),
      label: Text(context.l10n.viewOffline),
      onPressed: () => ref.read(viewOfflineNowProvider.notifier).set(true),
    );
  }
}
