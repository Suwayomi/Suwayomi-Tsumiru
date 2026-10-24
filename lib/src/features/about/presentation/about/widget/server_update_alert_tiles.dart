// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/app_utils.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../widgets/compact_switch.dart';
import '../../../../account/data/account_providers.dart';
import '../../../data/server_update_alerts_repository.dart';

/// WebUI's two server-update switches, inside About's Server card next to
/// "Check for server updates". Server managers only; anyone else (and any
/// load failure) sees nothing.
class ServerUpdateAlertTiles extends ConsumerWidget {
  const ServerUpdateAlertTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    if (!canManage) return const SizedBox.shrink();
    final settings = ref.watch(serverUpdateAlertSettingsProvider);
    return settings.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        if (data == null) return const SizedBox.shrink();
        final repository = ref.watch(serverUpdateAlertsRepositoryProvider);
        Future<void> save(Future<void> Function() action) async {
          final ok = await AppUtils.guard(() async {
            await action();
            return true;
          }, ref.read(toastProvider));
          if (ok == true && context.mounted) {
            ref.invalidate(serverUpdateAlertSettingsProvider);
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CompactSwitchListTile(
              controlAffinity: ListTileControlAffinity.trailing,
              title: Text(context.l10n.informAboutVersionUpdate),
              value: data.informVersionUpdated,
              onChanged: (value) => save(
                () => repository.write(
                  'serverInformVersionUpdated',
                  value,
                  data.metas,
                ),
              ),
            ),
            CompactSwitchListTile(
              controlAffinity: ListTileControlAffinity.trailing,
              title: Text(context.l10n.informAboutAvailableUpdate),
              value: data.informAvailableUpdate,
              onChanged: (value) => save(
                () => repository.write(
                  'serverInformAvailableUpdate',
                  value,
                  data.metas,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
