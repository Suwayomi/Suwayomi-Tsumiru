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

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.theme.colorScheme;
    final showAccount = ref.watch(showAccountEntryProvider);
    final account = ref.watch(currentAccountProvider);

    Widget row({
      required IconData icon,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
    }) => ListTile(
      leading: Icon(icon, color: colorScheme.onSurfaceVariant),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: onTap,
    );

    Widget groupCard(List<Widget> rows) {
      final children = <Widget>[];
      for (var i = 0; i < rows.length; i++) {
        if (i > 0) children.add(const Divider());
        children.add(rows[i]);
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      );
    }

    Widget heading(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 16, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );

    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.settings);
    final scaffold = Scaffold(
      appBar: topBar ? null : AppBar(title: title),
      body: WebSelectionArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              children: [
                heading(context.l10n.settingsGroupApp),
                groupCard([
                  row(
                    icon: Icons.tune_outlined,
                    title: context.l10n.general,
                    onTap: () => const GeneralSettingsRoute().push(context),
                  ),
                  row(
                    icon: Icons.palette_outlined,
                    title: context.l10n.appearance,
                    onTap: () => const AppearanceSettingsRoute().push(context),
                  ),
                  row(
                    icon: Icons.chrome_reader_mode_outlined,
                    title: context.l10n.reader,
                    onTap: () => const ReaderSettingsRoute().push(context),
                  ),
                  if (isKeyboardRuntime)
                    row(
                      icon: Icons.keyboard_outlined,
                      title: context.l10n.keyboardShortcuts,
                      onTap: () => const HotkeysSettingsRoute().push(context),
                    ),
                  if (isAndroidNative)
                    row(
                      icon: Icons.notifications_outlined,
                      title: context.l10n.notifications,
                      onTap: () =>
                          const NotificationsSettingsRoute().push(context),
                    ),
                ]),
                heading(context.l10n.library),
                groupCard([
                  row(
                    icon: Icons.collections_bookmark_outlined,
                    title: context.l10n.library,
                    onTap: () => const LibrarySettingsRoute().push(context),
                  ),
                  row(
                    icon: Icons.download_outlined,
                    title: context.l10n.downloads,
                    onTap: () => const DownloadsSettingsRoute().push(context),
                  ),
                  row(
                    icon: Icons.sync_outlined,
                    title: context.l10n.tracking,
                    onTap: () => const TrackingSettingsRoute().push(context),
                  ),
                  row(
                    icon: Icons.explore_outlined,
                    title: context.l10n.browse,
                    onTap: () => const BrowseSettingsRoute().push(context),
                  ),
                  row(
                    icon: Icons.settings_backup_restore_outlined,
                    title: context.l10n.backup,
                    onTap: () => const BackupRoute().push(context),
                  ),
                ]),
                heading(context.l10n.server),
                groupCard([
                  row(
                    icon: Icons.dns_outlined,
                    title: context.l10n.connection,
                    onTap: () => const ConnectionRoute().push(context),
                  ),
                  if (showAccount)
                    row(
                      icon: Icons.person_outlined,
                      title: context.l10n.accountTitle,
                      subtitle: account?.username,
                      onTap: () => const AccountRoute().push(context),
                    ),
                  row(
                    icon: Icons.cloud_sync_outlined,
                    title: context.l10n.sync,
                    onTap: () => const SyncRoute().push(context),
                  ),
                  row(
                    icon: Icons.admin_panel_settings_outlined,
                    title: context.l10n.serverAdmin,
                    onTap: () => const ServerSettingsRoute().push(context),
                  ),
                ]),
                const SizedBox(height: 12),
                row(
                  icon: Icons.build_outlined,
                  title: context.l10n.advanced,
                  onTap: () => const AdvancedRoute().push(context),
                ),
                row(
                  icon: Icons.info_outlined,
                  title: context.l10n.about,
                  onTap: () => const AboutRoute().push(context),
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
