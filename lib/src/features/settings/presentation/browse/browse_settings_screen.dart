// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../account/data/account_providers.dart';
import '../../../browse_center/data/extension_store_repository/extension_store_repository.dart';
import '../../controller/server_controller.dart';
import '../../domain/settings/settings.dart';
import '../../search/settings_search_registry.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
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
    // Native desktop draws the toolbar in the shell bar instead of an app
    // bar.
    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.browse);
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(leading: detailNavigationBackButton(context), title: title),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListTileTheme(
          data: ListTileThemeData(
            subtitleTextStyle: TextStyle(
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
          ),
          child: SettingsHighlightScope(
            child: Center(
              child: ConstrainedBox(
                constraints: settingsPageConstraints(context),
                child: ListView(
                  padding: settingsPagePadding(context),
                  children: [
                    if (!canManage)
                      ListTile(
                        subtitle: Text(
                          context.l10n.manageSettingsPermissionRequired,
                        ),
                      ),
                    // Permission-gated rows stay searchable while disabled:
                    // a missing MANAGE_SETTINGS only nulls onChanged, the
                    // tile stays on screen — so every entry below is always
                    // visible.
                    if (serverSettings.value != null) ...[
                      SettingsGroupHeading(
                        label: context.l10n.sources,
                        first: true,
                      ),
                      SettingsGroupCard(
                        children: [
                          SettingsHighlightTarget(
                            id: 'parallelSourceRequests',
                            child: SettingsPropTile(
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
                          ),
                          SettingsHighlightTarget(
                            id: 'localSourceLocation',
                            child: SettingsPropTile(
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
                              description:
                                  context.l10n.localSourceLocationDescription,
                              subtitle:
                                  (browseSettings?.localSourcePath).isNotBlank
                                  ? browseSettings?.localSourcePath
                                  : context.l10n.defaultFolderPath,
                            ),
                          ),
                        ],
                      ),
                    ],
                    SettingsGroupHeading(
                      label: context.l10n.extensions,
                      first: serverSettings.value == null,
                    ),
                    SettingsGroupCard(
                      children: [
                        if (serverSettings.value != null)
                          SettingsHighlightTarget(
                            id: 'extensionStores',
                            child: ListTile(
                              title: Text(context.l10n.extensionStores),
                              subtitle: Text(
                                storeCount == null
                                    ? context.l10n.extensionStoresDescription
                                    : context.l10n.nStores(storeCount),
                              ),
                              onTap: () =>
                                  const ExtensionStoreRoute().push(context),
                            ),
                          ),
                        const SettingsHighlightTarget(
                          id: 'showNsfw',
                          child: ShowNSFWTile(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: scaffold,
    );
  }
}
