// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../routes/router_config.dart';
import '../utils/extensions/custom_extensions.dart';
import 'emoticons.dart';
import 'server_unreachable_view.dart';

class ServerUnauthorizedView extends ConsumerWidget {
  const ServerUnauthorizedView({
    super.key,
    required this.message,
    this.onRetry,
    this.offlineEscape = false,
  });

  /// The server's own wording, kept so a permission denial still reads as one.
  final String message;
  final VoidCallback? onRetry;
  final bool offlineEscape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final webAuthBlocked = ref.watch(webAuthBlockedProvider);
    return Emoticons(
      iconData: FluentIcons.lock_closed_24_regular,
      title: context.l10n.serverSignedOutTitle,
      subTitle: webAuthBlocked ? context.l10n.webUnsupportedAuthMode : message,
      button: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: () => const ConnectionRoute().push(context),
            icon: const Icon(FluentIcons.plug_connected_24_regular),
            label: Text(context.l10n.serverUnreachableAction),
          ),
          if (offlineEscape) const ViewOfflineButton(),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(context.l10n.refresh)),
        ],
      ),
    );
  }
}
