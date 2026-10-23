import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/urls.dart';
import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/launch_url_in_web.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/platform/is_android_native.dart';
import '../../../../utils/platform/platform_runtime.dart';
import '../../../account/data/account_providers.dart';
import '../../../account/presentation/manage_users_screen.dart';
import '../../search/settings_search_registry.dart';
import '../general/general_screen.dart';
import '../server/server_network_screen.dart';
import '../server/server_opds_screen.dart';
import '../server/server_screen.dart';
import 'settings_pane_scope.dart';
import 'settings_screen.dart';

class _CloseSettingsIntent extends Intent {
  const _CloseSettingsIntent();
}

class SettingsWindow extends StatelessWidget {
  const SettingsWindow({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.windowSizeClass < WindowSizeClass.expanded) return child;
    final router = GoRouter.of(context);
    void close() {
      // One pop of the window page dismisses every page pushed inside it.
      // Navigator.of (not router.pop, which would only step back one inner
      // page) targets the branch navigator above the window's own.
      if (router.canPop()) {
        Navigator.of(context).pop();
        // A close that unwinds to the retired More screen (opened by URL
        // with no earlier screen: deep link, typed address, reload) lands
        // on Library on the desktop shell instead. Closes from a screen
        // already returned there through the pop above.
        if (context.usesDesktopShell &&
            router.state.uri.path == const MoreRoute().location) {
          const LibraryRoute(categoryId: 0).go(context);
        }
        return;
      }
      const LibraryRoute(categoryId: 0).go(context);
    }

    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) {
        final path = router.state.uri.path;
        final nested =
            path.endsWith('/edit-categories') ||
            path.endsWith('/extension-store') ||
            path.endsWith('/codes') ||
            path.endsWith('/image-processing') ||
            path.endsWith('/offline') ||
            path.endsWith('/duplicates');
        void back() => router.pop();
        return Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.escape): _CloseSettingsIntent(),
          },
          child: Actions(
            actions: {
              _CloseSettingsIntent: CallbackAction<_CloseSettingsIntent>(
                onInvoke: (_) {
                  close();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ModalBarrier(
                      color: Theme.of(
                        context,
                      ).colorScheme.scrim.withValues(alpha: .45),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 24,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 1080,
                          maxHeight: 760,
                        ),
                        child: SizedBox.expand(
                          key: const ValueKey('settingsWindow'),
                          child: Material(
                            color: context.colorScheme.surface,
                            elevation: 24,
                            shadowColor: context.colorScheme.shadow.withValues(
                              alpha: .55,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: context.colorScheme.outlineVariant,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 244,
                                  child: SettingsWindowPageList(path: path),
                                ),
                                VerticalDivider(
                                  width: 1,
                                  thickness: 1,
                                  color: context.colorScheme.outlineVariant,
                                ),
                                Expanded(
                                  child: SettingsPaneScope(
                                    nested: nested,
                                    onClose: close,
                                    onBack: back,
                                    tabs: _isServerPath(path)
                                        ? _ServerTabs(path: path)
                                        : null,
                                    child: child,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

bool _isServerPath(String path) =>
    path.startsWith('/more/settings/server') ||
    path.startsWith('/more/account/users');

class SettingsWindowPageBody extends ConsumerWidget {
  const SettingsWindowPageBody({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (child is SettingsScreen) return const GeneralScreen();
    if (child is ServerScreen) {
      final access = ref.watch(settledAccountAccessProvider);
      if (access.canManageUsers) return const ManageUsersScreen();
      if (access.allows(Enum$UserPermission.MANAGE_SETTINGS)) {
        return const ServerNetworkScreen();
      }
      return const ServerOpdsScreen();
    }
    return child;
  }
}

typedef _Destination = ({IconData icon, String title, String location});

class SettingsWindowPageList extends ConsumerStatefulWidget {
  const SettingsWindowPageList({super.key, required this.path});
  final String path;

  @override
  ConsumerState<SettingsWindowPageList> createState() =>
      _SettingsWindowPageListState();
}

class _SettingsWindowPageListState
    extends ConsumerState<SettingsWindowPageList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.colorScheme;
    final results = matchSettingsEntries(
      entries: allSettingsSearchEntries,
      l: l,
      query: _query,
      isVisible: (entry) => entry.visible(ref, context),
    );
    Widget row(_Destination destination) {
      final selected =
          widget.path == destination.location ||
          widget.path.startsWith('${destination.location}/') ||
          (destination.location == const GeneralSettingsRoute().location &&
              widget.path == const SettingsRoute().location) ||
          (destination.location == const ServerSettingsRoute().location &&
              _isServerPath(widget.path)) ||
          (destination.location == const ConnectionRoute().location &&
              widget.path == const AccountRoute().location) ||
          (destination.location == const SyncRoute().location &&
              [
                const SyncYomiSettingsRoute().location,
                const KoreaderSyncSettingsRoute().location,
              ].contains(widget.path));
      return SizedBox(
        height: 32,
        child: Material(
          color: selected
              ? cs.primary.withValues(alpha: .14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.push(destination.location),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    destination.icon,
                    size: 20,
                    color: selected ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      destination.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: selected ? cs.primary : cs.onSurface,
                        fontWeight: selected ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget group(String label, List<_Destination> destinations) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 24,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Text(
              label,
              style: context.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
        ...destinations.map(row),
      ],
    );
    return ColoredBox(
      color: cs.surfaceContainer,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: SizedBox(
              height: 36,
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                style: context.textTheme.bodySmall,
                decoration: InputDecoration(
                  hintText: l.settingsSearchHint,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: cs.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _query.trim().isNotEmpty
                ? ListView(
                    children: [
                      for (final entry in results)
                        SettingsSearchResultRow(
                          entry: entry,
                          query: _query,
                          onTap: () => entry.open(context),
                        ),
                    ],
                  )
                : ListView(
                    key: const ValueKey('settingsWindowPageList'),
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    children: [
                      group(l.settingsGroupApp, [
                        (
                          icon: Icons.tune_outlined,
                          title: l.general,
                          location: const GeneralSettingsRoute().location,
                        ),
                        (
                          icon: Icons.palette_outlined,
                          title: l.appearance,
                          location: const AppearanceSettingsRoute().location,
                        ),
                        (
                          icon: Icons.chrome_reader_mode_outlined,
                          title: l.reader,
                          location: const ReaderSettingsRoute().location,
                        ),
                        if (isKeyboardRuntime)
                          (
                            icon: Icons.keyboard_outlined,
                            title: l.keyboardShortcuts,
                            location: const HotkeysSettingsRoute().location,
                          ),
                        if (isAndroidNative)
                          (
                            icon: Icons.notifications_outlined,
                            title: l.notifications,
                            location:
                                const NotificationsSettingsRoute().location,
                          ),
                      ]),
                      group(l.library, [
                        (
                          icon: Icons.collections_bookmark_outlined,
                          title: l.library,
                          location: const LibrarySettingsRoute().location,
                        ),
                        (
                          icon: Icons.download_outlined,
                          title: l.downloads,
                          location: const DownloadsSettingsRoute().location,
                        ),
                        (
                          icon: Icons.sync_outlined,
                          title: l.tracking,
                          location: const TrackingSettingsRoute().location,
                        ),
                        (
                          icon: Icons.explore_outlined,
                          title: l.browse,
                          location: const BrowseSettingsRoute().location,
                        ),
                        (
                          icon: Icons.settings_backup_restore_outlined,
                          title: l.backup,
                          location: const BackupRoute().location,
                        ),
                      ]),
                      group(l.settingsGroupSuwayomi, [
                        (
                          icon: Icons.dns_outlined,
                          title: l.connection,
                          location: const ConnectionRoute().location,
                        ),
                        (
                          icon: Icons.cloud_sync_outlined,
                          title: l.sync,
                          location: const SyncRoute().location,
                        ),
                        (
                          icon: Icons.admin_panel_settings_outlined,
                          title: l.server,
                          location: const ServerSettingsRoute().location,
                        ),
                      ]),
                      const Divider(height: 16),
                      row((
                        icon: Icons.build_outlined,
                        title: l.advanced,
                        location: const AdvancedRoute().location,
                      )),
                      row((
                        icon: Icons.info_outline_rounded,
                        title: l.about,
                        location: const AboutRoute().location,
                      )),
                      SizedBox(
                        height: 32,
                        child: InkWell(
                          onTap: () => launchUrlInWeb(
                            context,
                            AppUrls.tachideskHelp.url,
                            ref.read(toastProvider),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.help_outline_rounded,
                                  size: 20,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  l.help,
                                  style: context.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ServerTabs extends ConsumerWidget {
  const _ServerTabs({required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final access = ref.watch(settledAccountAccessProvider);
    final manage = access.allows(Enum$UserPermission.MANAGE_SETTINGS);
    final tabs = <({String title, String location})>[
      if (access.canManageUsers)
        (title: l.serverUsers, location: const ManageUsersRoute().location),
      if (manage)
        (title: l.network, location: const ServerNetworkRoute().location),
      if (manage)
        (
          title: l.webInterface,
          location: const ServerWebInterfaceRoute().location,
        ),
      (title: l.opds, location: const ServerOpdsRoute().location),
      (title: l.images, location: const ServerImagesRoute().location),
      if (manage)
        (title: l.database, location: const ServerDatabaseRoute().location),
      if (manage) (title: l.logs, location: const ServerLogsRoute().location),
    ];
    var index = tabs.indexWhere((tab) => path.startsWith(tab.location));
    if (path.endsWith('/image-processing')) {
      index = tabs.indexWhere(
        (tab) => tab.location == const ServerImagesRoute().location,
      );
    }
    return DefaultTabController(
      key: ValueKey('$path:${tabs.length}'),
      length: tabs.length,
      initialIndex: index < 0 ? 0 : index,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [for (final tab in tabs) Tab(text: tab.title)],
        onTap: (index) => context.push(tabs[index].location),
      ),
    );
  }
}
