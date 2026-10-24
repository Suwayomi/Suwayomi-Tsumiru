// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/platform/is_android_native.dart';
import '../../../../utils/platform/platform_runtime.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../../widgets/web_selection_area.dart';
import '../../../account/data/account_providers.dart';
import '../../../quick_open/presentation/unified_search/phone_search_view.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
import '../library/widgets/persistent_search_bar/persistent_search_bar.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showAccount = ref.watch(showAccountEntryProvider);
    final account = ref.watch(currentAccountProvider);
    final phone = context.windowSizeClass == WindowSizeClass.compact;
    final persistentBox =
        phone && ref.watch(libraryPersistentSearchBarProvider).ifNull();

    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.settings);
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
              leading: detailNavigationBackButton(context),
              title: title,
              bottom: persistentBox
                  ? const PhoneSearchBoxBottom(origin: PhoneSearchOrigin.plain)
                  : null,
              actions: [
                if (phone && !persistentBox)
                  const PhoneSearchEntry(origin: PhoneSearchOrigin.plain),
              ],
            ),
      body: WebSelectionArea(
        child: Center(
          child: ConstrainedBox(
            constraints: settingsPageConstraints(context),
            child: ListView(
              padding: settingsPagePadding(context),
              children: [
                SettingsGroupHeading(
                  label: context.l10n.settingsGroupApp,
                  first: true,
                ),
                SettingsGroupCard(
                  children: [
                    SettingsGroupRow(
                      icon: FluentIcons.options_24_regular,
                      title: context.l10n.general,
                      onTap: () => const GeneralSettingsRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: FluentIcons.color_24_regular,
                      title: context.l10n.appearance,
                      onTap: () =>
                          const AppearanceSettingsRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: FluentIcons.book_open_24_regular,
                      title: context.l10n.reader,
                      onTap: () => const ReaderSettingsRoute().push(context),
                    ),
                    if (isKeyboardRuntime)
                      SettingsGroupRow(
                        icon: FluentIcons.keyboard_24_regular,
                        title: context.l10n.keyboardShortcuts,
                        onTap: () => const HotkeysSettingsRoute().push(context),
                      ),
                    if (isAndroidNative)
                      SettingsGroupRow(
                        icon: FluentIcons.alert_24_regular,
                        title: context.l10n.notifications,
                        onTap: () =>
                            const NotificationsSettingsRoute().push(context),
                      ),
                  ],
                ),
                SettingsGroupHeading(label: context.l10n.library),
                SettingsGroupCard(
                  children: [
                    SettingsGroupRow(
                      icon: FluentIcons.library_24_regular,
                      title: context.l10n.library,
                      onTap: () => const LibrarySettingsRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: FluentIcons.arrow_download_24_regular,
                      title: context.l10n.downloads,
                      onTap: () => const DownloadsSettingsRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: FluentIcons.arrow_sync_24_regular,
                      title: context.l10n.tracking,
                      onTap: () => const TrackingSettingsRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: FluentIcons.compass_northwest_24_regular,
                      title: context.l10n.browse,
                      onTap: () => const BrowseSettingsRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: FluentIcons.arrow_counterclockwise_24_regular,
                      title: context.l10n.backup,
                      onTap: () => const BackupRoute().push(context),
                    ),
                  ],
                ),
                SettingsGroupHeading(label: context.l10n.settingsGroupSuwayomi),
                SettingsGroupCard(
                  children: [
                    SettingsGroupRow(
                      icon: FluentIcons.server_24_regular,
                      title: context.l10n.connection,
                      subtitle: showAccount ? account?.username : null,
                      onTap: () => const ConnectionRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: FluentIcons.cloud_sync_24_regular,
                      title: context.l10n.sync,
                      onTap: () => const SyncRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: FluentIcons.desktop_24_regular,
                      title: context.l10n.server,
                      onTap: () => const ServerSettingsRoute().push(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SettingsGroupCard(
                  children: [
                    SettingsGroupRow(
                      icon: FluentIcons.wrench_24_regular,
                      title: context.l10n.advanced,
                      onTap: () => const AdvancedRoute().push(context),
                    ),
                  ],
                ),
              ],
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
