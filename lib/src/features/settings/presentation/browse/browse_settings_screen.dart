// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../account/data/account_providers.dart';
import '../../../browse_center/data/extension_store_repository/extension_store_repository.dart';
import '../../controller/server_controller.dart';
import '../../domain/settings/settings.dart';
import 'data/browse_settings_repository.dart';
import 'widgets/show_nsfw_switch/show_nsfw_switch.dart';

class BrowseSettingsScreen extends ConsumerWidget {
  const BrowseSettingsScreen({super.key});

  @override
  Widget build(context, ref) {
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    final repository = ref.watch(browseSettingsRepositoryProvider);
    final serverSettings = ref.watch(settingsProvider);
    final BrowserSettingsDto? browseSettings = serverSettings.value;
    onRefresh() => ref.refresh(settingsProvider.future);
    final storeCount = ref.watch(extensionStoreListProvider).value?.totalCount;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.browse)),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListTileTheme(
          data: ListTileThemeData(
            subtitleTextStyle: TextStyle(
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
          ),
          child: ListView(
            children: [
              const ShowNSFWTile(),
              Row(
                children: [
                  const Gap(16),
                  Icon(
                    Icons.info_outline_rounded,
                    color: context.theme.colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
                  const Gap(10),
                  Expanded(
                    child: Text(
                      context.l10n.nsfwInfo,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Gap(10),
                ],
              ),
              const Divider(),
              if (!canManage)
                ListTile(
                  subtitle: Text(context.l10n.manageSettingsPermissionRequired),
                ),
              if (serverSettings.value != null) ...[
                SettingsPropTile(
                  leading: const Icon(Icons.swap_vert_rounded),
                  title: context.l10n.parallelSourceRequest,
                  subtitle: context.l10n.nSources(
                    (browseSettings?.maxSourcesInParallel).ifNull(),
                  ),
                  type: SettingsPropType.numberSlider(
                    min: 1,
                    max: 20,
                    value: browseSettings?.maxSourcesInParallel,
                    onChanged: canManage
                        ? repository.updateSourceInParallel
                        : null,
                  ),
                ),
                SettingsPropTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: context.l10n.localSourceLocation,
                  type: SettingsPropType.textField(
                    hintText: context.l10n.enterProp(
                      context.l10n.localSourceLocation,
                    ),
                    value: browseSettings?.localSourcePath,
                    onChanged: canManage
                        ? repository.updateLocalSourcePath
                        : null,
                  ),
                  description: context.l10n.localSourceLocationDescription,
                  subtitle: browseSettings?.localSourcePath,
                ),
                ListTile(
                  leading: const Icon(Icons.extension_rounded),
                  title: Text(context.l10n.extensionStores),
                  subtitle: Text(
                    storeCount == null
                        ? context.l10n.extensionStoresDescription
                        : context.l10n.nStores(storeCount),
                  ),
                  onTap: () => const ExtensionStoreRoute().push(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
