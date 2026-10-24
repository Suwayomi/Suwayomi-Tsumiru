// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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

class ServerUnreachableView extends ConsumerWidget {
  const ServerUnreachableView({
    super.key,
    this.onRetry,
    this.offlineEscape = false,
    this.webNotFoundVerdict = false,
  });

  final VoidCallback? onRetry;

  /// Enable only on screens that honor the offline pin.
  final bool offlineEscape;

  final bool webNotFoundVerdict;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Gate outside the button so a hidden child cannot reserve Column spacing.
    final hasCatalog =
        ref.watch(offlineCatalogAvailableProvider).value ?? false;
    final webAuthBlocked = ref.watch(webAuthBlockedProvider);
    final isWeb = ref.watch(isWebProvider);
    return Emoticons(
      iconData: FluentIcons.cloud_off_24_regular,
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
            icon: const Icon(FluentIcons.plug_connected_24_regular),
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

/// User-triggered offline bypass; parents should gate visibility to avoid Column spacing.
class ViewOfflineButton extends ConsumerWidget {
  const ViewOfflineButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasCatalog =
        ref.watch(offlineCatalogAvailableProvider).value ?? false;
    if (!hasCatalog) return const SizedBox.shrink();
    return TextButton.icon(
      icon: const Icon(FluentIcons.cloud_off_24_regular),
      label: Text(context.l10n.viewOffline),
      onPressed: () => ref.read(viewOfflineNowProvider.notifier).set(true),
    );
  }
}
