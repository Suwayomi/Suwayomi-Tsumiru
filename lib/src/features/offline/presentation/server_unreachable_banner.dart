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

/// Inline banner shown in the library while the server can't be reached.
///
/// It lives on the library because that's where the reachability signal is
/// detected, and where the case it exists for happens: browsing a stale cached
/// library without realising you're offline. It sits inline (not via
/// `ScaffoldMessenger`) so it never contends with the app-wide re-auth banner
/// for the shared banner slot.
class ServerUnreachableBanner extends ConsumerWidget {
  const ServerUnreachableBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(serverUnreachableProvider)) return const SizedBox.shrink();

    return MaterialBanner(
      content: Text(context.l10n.serverUnreachableTitle),
      leading: const Icon(Icons.cloud_off_rounded),
      actions: [
        TextButton(
          onPressed: () => const ConnectionRoute().go(context),
          child: Text(context.l10n.serverUnreachableAction),
        ),
      ],
    );
  }
}
