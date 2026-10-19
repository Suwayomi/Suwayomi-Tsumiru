part of '../router_config.dart';

class MoreBranch extends StatefulShellBranchData {
  const MoreBranch();
}

class MoreRoute extends GoRouteData with $MoreRoute {
  const MoreRoute();
  @override
  Page<void> buildPage(context, state) =>
      const NoTransitionPage(child: MoreScreen());
}

// Everything below opens above the bottom nav, the way Mihon and Komikku push
// settings out of the tab system. Keeping them inside the More branch left the
// nav bar on screen, made the tab restore whatever screen you were last on,
// and forced a second Back out of the branch stack.
//
// The key is the quick-open shell's, not rootNavigatorKey: GlobalShortcutHost
// lives inside that shell, so a root-navigator page would be its sibling and
// lose every global shortcut. ReaderRoute and GlobalSearchRoute do the same.
//
// Each screen is wrapped in DetailNavigationShellScreen so the sidebar stays
// visible on tablet/desktop. It returns the child unchanged on phone.

class AboutRoute extends GoRouteData with $AboutRoute {
  const AboutRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: AboutScreen());
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: SettingsScreen());
}

class LibrarySettingsRoute extends GoRouteData with $LibrarySettingsRoute {
  const LibrarySettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: LibrarySettingsScreen());
}

class EditCategoriesRoute extends GoRouteData with $EditCategoriesRoute {
  const EditCategoriesRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: EditCategoryScreen());
}

class ReaderSettingsRoute extends GoRouteData with $ReaderSettingsRoute {
  const ReaderSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: ReaderSettingsScreen());
}

class AppearanceSettingsRoute extends GoRouteData
    with $AppearanceSettingsRoute {
  const AppearanceSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: AppearanceScreen());
}

class GeneralSettingsRoute extends GoRouteData with $GeneralSettingsRoute {
  const GeneralSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: GeneralScreen());
}

class BrowseSettingsRoute extends GoRouteData with $BrowseSettingsRoute {
  const BrowseSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: BrowseSettingsScreen());
}

class ExtensionStoreRoute extends GoRouteData with $ExtensionStoreRoute {
  const ExtensionStoreRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: ExtensionStoreScreen());
}

class BackupRoute extends GoRouteData with $BackupRoute {
  const BackupRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: BackupScreen());
}

class ServerSettingsRoute extends GoRouteData with $ServerSettingsRoute {
  const ServerSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: ServerScreen());
}

class DownloadsSettingsRoute extends GoRouteData with $DownloadsSettingsRoute {
  const DownloadsSettingsRoute({this.highlight, this.tab});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  /// Tab to open alongside [highlight]: 0 Server, 1 On device. Null (or an
  /// out-of-range value) opens the Server tab. Any tabbed settings page can
  /// reuse this `highlight` + `tab` pair; the entry's `tabIndex` carries it.
  final int? tab;

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => DetailNavigationShellScreen(
    child: DownloadsSettingsScreen(initialTab: tab ?? 0),
  );
}

class OfflineSettingsRoute extends GoRouteData with $OfflineSettingsRoute {
  const OfflineSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: OfflineSettingsScreen());
}

class NotificationsSettingsRoute extends GoRouteData
    with $NotificationsSettingsRoute {
  const NotificationsSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: NotificationsSettingsScreen());
}

class ConnectionRoute extends GoRouteData with $ConnectionRoute {
  const ConnectionRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: ConnectionScreen());
}

class TrackingSettingsRoute extends GoRouteData with $TrackingSettingsRoute {
  const TrackingSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: TrackingSettingsScreen());
}

class SyncYomiSettingsRoute extends GoRouteData with $SyncYomiSettingsRoute {
  const SyncYomiSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: SyncYomiSettingsScreen());
}

class KoreaderSyncSettingsRoute extends GoRouteData
    with $KoreaderSyncSettingsRoute {
  const KoreaderSyncSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: KoreaderSyncSettingsScreen());
}

class HotkeysSettingsRoute extends GoRouteData with $HotkeysSettingsRoute {
  const HotkeysSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const DetailNavigationShellScreen(child: HotkeysSettingsScreen());
}

class AccountRoute extends GoRouteData with $AccountRoute {
  const AccountRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: AccountScreen());
}

class ManageUsersRoute extends GoRouteData with $ManageUsersRoute {
  const ManageUsersRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: ManageUsersScreen());
}
