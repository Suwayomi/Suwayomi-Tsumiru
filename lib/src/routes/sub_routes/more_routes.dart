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

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const AboutScreen());
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: SettingsScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const SettingsScreen());
}

class LibrarySettingsRoute extends GoRouteData with $LibrarySettingsRoute {
  const LibrarySettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: LibrarySettingsScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const LibrarySettingsScreen());
}

class EditCategoriesRoute extends GoRouteData with $EditCategoriesRoute {
  const EditCategoriesRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: EditCategoryScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const EditCategoryScreen());
}

class ReaderSettingsRoute extends GoRouteData with $ReaderSettingsRoute {
  const ReaderSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: ReaderSettingsScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const ReaderSettingsScreen());
}

class AppearanceSettingsRoute extends GoRouteData
    with $AppearanceSettingsRoute {
  const AppearanceSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: AppearanceScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const AppearanceScreen());
}

class GeneralSettingsRoute extends GoRouteData with $GeneralSettingsRoute {
  const GeneralSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: GeneralScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const GeneralScreen());
}

class BrowseSettingsRoute extends GoRouteData with $BrowseSettingsRoute {
  const BrowseSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: BrowseSettingsScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const BrowseSettingsScreen());
}

class ExtensionStoreRoute extends GoRouteData with $ExtensionStoreRoute {
  const ExtensionStoreRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: ExtensionStoreScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const ExtensionStoreScreen());
}

class BackupRoute extends GoRouteData with $BackupRoute {
  const BackupRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: BackupScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const BackupScreen());
}

class ServerSettingsRoute extends GoRouteData with $ServerSettingsRoute {
  const ServerSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: ServerScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const ServerScreen());
}

class DownloadsSettingsRoute extends GoRouteData with $DownloadsSettingsRoute {
  const DownloadsSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: DownloadsSettingsScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const DownloadsSettingsScreen());
}

class OfflineSettingsRoute extends GoRouteData with $OfflineSettingsRoute {
  const OfflineSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: OfflineSettingsScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const OfflineSettingsScreen());
}

class NotificationsSettingsRoute extends GoRouteData
    with $NotificationsSettingsRoute {
  const NotificationsSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: NotificationsSettingsScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const NotificationsSettingsScreen());
}

class ConnectionRoute extends GoRouteData with $ConnectionRoute {
  const ConnectionRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: ConnectionScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const ConnectionScreen());
}

class TrackingSettingsRoute extends GoRouteData with $TrackingSettingsRoute {
  const TrackingSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: TrackingSettingsScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const TrackingSettingsScreen());
}

class SyncYomiSettingsRoute extends GoRouteData with $SyncYomiSettingsRoute {
  const SyncYomiSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: SyncYomiSettingsScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const SyncYomiSettingsScreen());
}

class KoreaderSyncSettingsRoute extends GoRouteData
    with $KoreaderSyncSettingsRoute {
  const KoreaderSyncSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: KoreaderSyncSettingsScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const KoreaderSyncSettingsScreen());
}

class HotkeysSettingsRoute extends GoRouteData with $HotkeysSettingsRoute {
  const HotkeysSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const DetailNavigationShellScreen(child: HotkeysSettingsScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const HotkeysSettingsScreen());
}

class AccountRoute extends GoRouteData with $AccountRoute {
  const AccountRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: AccountScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const AccountScreen());
}

class ManageUsersRoute extends GoRouteData with $ManageUsersRoute {
  const ManageUsersRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) =>
      const DetailNavigationShellScreen(child: ManageUsersScreen());

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const ManageUsersScreen());
}
