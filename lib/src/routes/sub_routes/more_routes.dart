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

class AboutRoute extends GoRouteData with $AboutRoute {
  const AboutRoute();

  @override
  Widget build(context, state) => const AboutScreen();
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();

  @override
  Widget build(context, state) => const SettingsScreen();
}

class LibrarySettingsRoute extends GoRouteData with $LibrarySettingsRoute {
  const LibrarySettingsRoute();

  @override
  Widget build(context, state) => const LibrarySettingsScreen();
}

class EditCategoriesRoute extends GoRouteData with $EditCategoriesRoute {
  const EditCategoriesRoute();

  @override
  Widget build(context, state) => const EditCategoryScreen();
}

class ReaderSettingsRoute extends GoRouteData with $ReaderSettingsRoute {
  const ReaderSettingsRoute();

  @override
  Widget build(context, state) => const ReaderSettingsScreen();
}

class AppearanceSettingsRoute extends GoRouteData with $AppearanceSettingsRoute {
  const AppearanceSettingsRoute();

  @override
  Widget build(context, state) => const AppearanceScreen();
}

class GeneralSettingsRoute extends GoRouteData with $GeneralSettingsRoute {
  const GeneralSettingsRoute();

  @override
  Widget build(context, state) => const GeneralScreen();
}

class BrowseSettingsRoute extends GoRouteData with $BrowseSettingsRoute {
  const BrowseSettingsRoute();

  @override
  Widget build(context, state) => const BrowseSettingsScreen();
}

class ExtensionRepositoryRoute extends GoRouteData with $ExtensionRepositoryRoute {
  const ExtensionRepositoryRoute();

  @override
  Widget build(context, state) => const ExtensionRepositoryScreen();
}

class BackupRoute extends GoRouteData with $BackupRoute {
  const BackupRoute();
  @override
  Widget build(context, state) => const BackupScreen();
}

class ServerSettingsRoute extends GoRouteData with $ServerSettingsRoute {
  const ServerSettingsRoute();

  @override
  Widget build(context, state) => const ServerScreen();
}

class DownloadsSettingsRoute extends GoRouteData with $DownloadsSettingsRoute {
  const DownloadsSettingsRoute();

  @override
  Widget build(context, state) => const DownloadsSettingsScreen();
}

class OfflineSettingsRoute extends GoRouteData with $OfflineSettingsRoute {
  const OfflineSettingsRoute();

  @override
  Widget build(context, state) => const OfflineSettingsScreen();
}

class ConnectionRoute extends GoRouteData with $ConnectionRoute {
  const ConnectionRoute();

  @override
  Widget build(context, state) => const ConnectionScreen();
}

class TrackingSettingsRoute extends GoRouteData with $TrackingSettingsRoute {
  const TrackingSettingsRoute();

  @override
  Widget build(context, state) => const TrackingSettingsScreen();
}

class HotkeysSettingsRoute extends GoRouteData with $HotkeysSettingsRoute {
  const HotkeysSettingsRoute();
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const HotkeysSettingsScreen();
}
