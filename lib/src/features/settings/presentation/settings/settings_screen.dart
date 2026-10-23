// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
    // Phone searches from the app-bar entry (or the box under the title when
    // the persistent setting is on), like More does.
    final phone = context.windowSizeClass == WindowSizeClass.compact;
    final persistentBox =
        phone && ref.watch(libraryPersistentSearchBarProvider).ifNull();

    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.settings);
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
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
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              children: [
                SettingsGroupHeading(
                  label: context.l10n.settingsGroupApp,
                  first: true,
                ),
                SettingsGroupCard(
                  children: [
                    SettingsGroupRow(
                      icon: Icons.tune_outlined,
                      title: context.l10n.general,
                      onTap: () => const GeneralSettingsRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: Icons.palette_outlined,
                      title: context.l10n.appearance,
                      onTap: () =>
                          const AppearanceSettingsRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: Icons.chrome_reader_mode_outlined,
                      title: context.l10n.reader,
                      onTap: () => const ReaderSettingsRoute().push(context),
                    ),
                    if (isKeyboardRuntime)
                      SettingsGroupRow(
                        icon: Icons.keyboard_outlined,
                        title: context.l10n.keyboardShortcuts,
                        onTap: () => const HotkeysSettingsRoute().push(context),
                      ),
                    if (isAndroidNative)
                      SettingsGroupRow(
                        icon: Icons.notifications_outlined,
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
                      icon: Icons.collections_bookmark_outlined,
                      title: context.l10n.library,
                      onTap: () => const LibrarySettingsRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: Icons.download_outlined,
                      title: context.l10n.downloads,
                      onTap: () => const DownloadsSettingsRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: Icons.sync_outlined,
                      title: context.l10n.tracking,
                      onTap: () => const TrackingSettingsRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: Icons.explore_outlined,
                      title: context.l10n.browse,
                      onTap: () => const BrowseSettingsRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: Icons.settings_backup_restore_outlined,
                      title: context.l10n.backup,
                      onTap: () => const BackupRoute().push(context),
                    ),
                  ],
                ),
                SettingsGroupHeading(label: context.l10n.settingsGroupSuwayomi),
                SettingsGroupCard(
                  children: [
                    SettingsGroupRow(
                      icon: Icons.dns_outlined,
                      title: context.l10n.connection,
                      subtitle: showAccount ? account?.username : null,
                      onTap: () => const ConnectionRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: Icons.cloud_sync_outlined,
                      title: context.l10n.sync,
                      onTap: () => const SyncRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: Icons.admin_panel_settings_outlined,
                      title: context.l10n.server,
                      onTap: () => const ServerSettingsRoute().push(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SettingsGroupCard(
                  children: [
                    SettingsGroupRow(
                      icon: Icons.build_outlined,
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
