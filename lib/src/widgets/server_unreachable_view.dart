// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../routes/router_config.dart';
import '../utils/extensions/custom_extensions.dart';
import 'emoticons.dart';

/// Shown when a request failed because the server couldn't be reached (wrong
/// URL, server down, no network) — as opposed to an auth or server-side error.
///
/// It points straight at Connection settings, the one screen where a wrong
/// server URL is fixed, so a disconnected user is never stranded on a blank
/// screen with no way forward.
class ServerUnreachableView extends StatelessWidget {
  const ServerUnreachableView({super.key, this.onRetry});

  /// Optional retry (re-runs the failed query). Omitted where there's nothing
  /// to re-fetch.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Emoticons(
      iconData: Icons.cloud_off_rounded,
      title: context.l10n.serverUnreachableTitle,
      subTitle: context.l10n.serverUnreachableSubtitle,
      button: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.tonalIcon(
            onPressed: () => const ConnectionRoute().go(context),
            icon: const Icon(Icons.settings_ethernet_rounded),
            label: Text(context.l10n.serverUnreachableAction),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.refresh),
            ),
        ],
      ),
    );
  }
}
