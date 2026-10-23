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

  Widget get _screen => const AboutScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

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

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  Widget get _screen => const LibrarySettingsScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class EditCategoriesRoute extends GoRouteData with $EditCategoriesRoute {
  const EditCategoriesRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

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

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

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

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

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

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

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

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  Widget get _screen => const BrowseSettingsScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ExtensionStoreRoute extends GoRouteData with $ExtensionStoreRoute {
  const ExtensionStoreRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

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

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  Widget get _screen => const BackupScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ServerSettingsRoute extends GoRouteData with $ServerSettingsRoute {
  const ServerSettingsRoute({this.highlight});

  /// Id of the setting to scroll to and pulse after navigation, matching a
  /// [SettingsHighlightTarget] on the page. Null opens the page plainly.
  final String? highlight;

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  Widget get _screen => const ServerScreen();

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

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

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

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  Widget get _screen => DownloadsSettingsScreen(initialTab: tab ?? 0);

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class OfflineSettingsRoute extends GoRouteData with $OfflineSettingsRoute {
  const OfflineSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

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

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

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

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

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

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

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

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  Widget get _screen => const SyncYomiSettingsScreen();

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

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  Widget get _screen => const KoreaderSyncSettingsScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class HotkeysSettingsRoute extends GoRouteData with $HotkeysSettingsRoute {
  const HotkeysSettingsRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

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

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  Widget get _screen => const AccountScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ManageUsersRoute extends GoRouteData with $ManageUsersRoute {
  const ManageUsersRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  Widget get _screen => const ManageUsersScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class AccountCodesRoute extends GoRouteData with $AccountCodesRoute {
  const AccountCodesRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  Widget get _screen => const AccountCodesScreen();

  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}
