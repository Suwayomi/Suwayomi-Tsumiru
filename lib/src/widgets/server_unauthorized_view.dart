// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../routes/router_config.dart';
import '../utils/extensions/custom_extensions.dart';
import 'emoticons.dart';
import 'server_unreachable_view.dart';

/// Shown when the server rejected the app's credentials — the auth sibling of
/// [ServerUnreachableView], and it points at the same screen, because signing
/// in again is the only thing that fixes it. Without this, Refresh is the only
/// action and it can only fail the same way.
class ServerUnauthorizedView extends StatelessWidget {
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
  Widget build(BuildContext context) => Emoticons(
    iconData: Icons.lock_outline_rounded,
    title: context.l10n.serverSignedOutTitle,
    subTitle: message,
    button: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => const ConnectionRoute().push(context),
          icon: const Icon(Icons.settings_ethernet_rounded),
          label: Text(context.l10n.serverUnreachableAction),
        ),
        if (offlineEscape) const ViewOfflineButton(),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: Text(context.l10n.refresh)),
      ],
    ),
  );
}
