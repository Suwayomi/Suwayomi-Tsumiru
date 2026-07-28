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

class AboutRoute extends GoRouteData with $AboutRoute {
  const AboutRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const AboutScreen();
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const SettingsScreen();
}

class LibrarySettingsRoute extends GoRouteData with $LibrarySettingsRoute {
  const LibrarySettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const LibrarySettingsScreen();
}

class EditCategoriesRoute extends GoRouteData with $EditCategoriesRoute {
  const EditCategoriesRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const EditCategoryScreen();
}

class ReaderSettingsRoute extends GoRouteData with $ReaderSettingsRoute {
  const ReaderSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const ReaderSettingsScreen();
}

class AppearanceSettingsRoute extends GoRouteData with $AppearanceSettingsRoute {
  const AppearanceSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const AppearanceScreen();
}

class GeneralSettingsRoute extends GoRouteData with $GeneralSettingsRoute {
  const GeneralSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const GeneralScreen();
}

class BrowseSettingsRoute extends GoRouteData with $BrowseSettingsRoute {
  const BrowseSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const BrowseSettingsScreen();
}

class ExtensionStoreRoute extends GoRouteData with $ExtensionStoreRoute {
  const ExtensionStoreRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const ExtensionStoreScreen();
}

class BackupRoute extends GoRouteData with $BackupRoute {
  const BackupRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const BackupScreen();
}

class ServerSettingsRoute extends GoRouteData with $ServerSettingsRoute {
  const ServerSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const ServerScreen();
}

class DownloadsSettingsRoute extends GoRouteData with $DownloadsSettingsRoute {
  const DownloadsSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const DownloadsSettingsScreen();
}

class OfflineSettingsRoute extends GoRouteData with $OfflineSettingsRoute {
  const OfflineSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const OfflineSettingsScreen();
}

class NotificationsSettingsRoute extends GoRouteData
    with $NotificationsSettingsRoute {
  const NotificationsSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const NotificationsSettingsScreen();
}

class ConnectionRoute extends GoRouteData with $ConnectionRoute {
  const ConnectionRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const ConnectionScreen();
}

class TrackingSettingsRoute extends GoRouteData with $TrackingSettingsRoute {
  const TrackingSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const TrackingSettingsScreen();
}

class HotkeysSettingsRoute extends GoRouteData with $HotkeysSettingsRoute {
  const HotkeysSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const HotkeysSettingsScreen();
}
