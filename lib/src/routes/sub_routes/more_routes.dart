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

// A shared navigator keeps nested settings pages inside the desktop window.
// It stays under the quick-open shell so global shortcuts remain available.

class AboutRoute extends GoRouteData with $AboutRoute {
  const AboutRoute();

  Widget get _screen => const AboutScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();

  Widget get _screen => const SettingsScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class LibrarySettingsRoute extends GoRouteData with $LibrarySettingsRoute {
  const LibrarySettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const LibrarySettingsScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class EditCategoriesRoute extends GoRouteData with $EditCategoriesRoute {
  const EditCategoriesRoute();

  Widget get _screen => const EditCategoryScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ReaderSettingsRoute extends GoRouteData with $ReaderSettingsRoute {
  const ReaderSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const ReaderSettingsScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class AppearanceSettingsRoute extends GoRouteData
    with $AppearanceSettingsRoute {
  const AppearanceSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const AppearanceScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class GeneralSettingsRoute extends GoRouteData with $GeneralSettingsRoute {
  const GeneralSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const GeneralScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class BrowseSettingsRoute extends GoRouteData with $BrowseSettingsRoute {
  const BrowseSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const BrowseSettingsScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ExtensionStoreRoute extends GoRouteData with $ExtensionStoreRoute {
  const ExtensionStoreRoute();

  Widget get _screen => const ExtensionStoreScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class BackupRoute extends GoRouteData with $BackupRoute {
  const BackupRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const BackupScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ServerSettingsRoute extends GoRouteData with $ServerSettingsRoute {
  const ServerSettingsRoute();

  Widget get _screen => const ServerScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ServerNetworkRoute extends GoRouteData with $ServerNetworkRoute {
  const ServerNetworkRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const ServerNetworkScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ServerWebInterfaceRoute extends GoRouteData
    with $ServerWebInterfaceRoute {
  const ServerWebInterfaceRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const ServerWebInterfaceScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ServerOpdsRoute extends GoRouteData with $ServerOpdsRoute {
  const ServerOpdsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const ServerOpdsScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ServerImagesRoute extends GoRouteData with $ServerImagesRoute {
  const ServerImagesRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const ServerImagesScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ServerSignInRoute extends GoRouteData with $ServerSignInRoute {
  const ServerSignInRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const ServerSignInScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ServerDatabaseRoute extends GoRouteData with $ServerDatabaseRoute {
  const ServerDatabaseRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const ServerDatabaseScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ServerLogsRoute extends GoRouteData with $ServerLogsRoute {
  const ServerLogsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const ServerLogsScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class SyncRoute extends GoRouteData with $SyncRoute {
  const SyncRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const SyncScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class AdvancedRoute extends GoRouteData with $AdvancedRoute {
  const AdvancedRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const AdvancedScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ImageProcessingRoute extends GoRouteData with $ImageProcessingRoute {
  const ImageProcessingRoute({this.type = 'download'});

  /// Which conversion map the editor opens: `download` or `serve`.
  final String type;

  Widget get _screen => ImageProcessingScreen(
    kind: type == 'serve'
        ? ImageProcessingKind.serve
        : ImageProcessingKind.download,
  );

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
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

  Widget get _screen => DownloadsSettingsScreen(initialTab: tab ?? 0);

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class OfflineSettingsRoute extends GoRouteData with $OfflineSettingsRoute {
  const OfflineSettingsRoute();

  Widget get _screen => const OfflineSettingsScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class NotificationsSettingsRoute extends GoRouteData
    with $NotificationsSettingsRoute {
  const NotificationsSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const NotificationsSettingsScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ConnectionRoute extends GoRouteData with $ConnectionRoute {
  const ConnectionRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const ConnectionScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class TrackingSettingsRoute extends GoRouteData with $TrackingSettingsRoute {
  const TrackingSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  Widget get _screen => const TrackingSettingsScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class SyncYomiSettingsRoute extends GoRouteData with $SyncYomiSettingsRoute {
  const SyncYomiSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  // The SyncYomi page merged into the Sync page, so the old link lands here.
  Widget get _screen => const SyncScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class KoreaderSyncSettingsRoute extends GoRouteData
    with $KoreaderSyncSettingsRoute {
  const KoreaderSyncSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  // The KOReader Sync page merged into the Sync page, so the old link lands here.
  Widget get _screen => const SyncScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class HotkeysSettingsRoute extends GoRouteData with $HotkeysSettingsRoute {
  const HotkeysSettingsRoute();

  Widget get _screen => const HotkeysSettingsScreen();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class AccountRoute extends GoRouteData with $AccountRoute {
  const AccountRoute();

  // The Account page folded into Connection; the old link lands there.
  Widget get _screen => const ConnectionScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ManageUsersRoute extends GoRouteData with $ManageUsersRoute {
  const ManageUsersRoute();

  Widget get _screen => const ManageUsersScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class AccountCodesRoute extends GoRouteData with $AccountCodesRoute {
  const AccountCodesRoute();

  Widget get _screen => const AccountCodesScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class SettingsWindowShellRoute extends ShellRouteData {
  const SettingsWindowShellRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Page<void> pageBuilder(context, state, navigator) =>
      CustomTransitionPage<void>(
        key: state.pageKey,
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            child,
        child: SettingsWindow(child: navigator),
      );
}

class SettingsLibraryDuplicatesRoute extends GoRouteData
    with $SettingsLibraryDuplicatesRoute {
  const SettingsLibraryDuplicatesRoute();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, const LibraryDuplicatesScreen());
}
