part of '../router_config.dart';

class BrowserBranch extends StatefulShellBranchData {
  const BrowserBranch();
  static final $initialLocation = const BrowseSourceRoute().location;
}

class BrowseShellRoute extends StatefulShellRouteData {
  const BrowseShellRoute();

  static final $navigatorKey = _browseNavigatorKey;

  static Widget $navigatorContainerBuilder(
    BuildContext context,
    StatefulNavigationShell navigationShell,
    List<Widget> children,
  ) => BrowseScreen(
    key: const ValueKey('browse'),
    currentIndex: navigationShell.currentIndex,
    onDestinationSelected: (index) => navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    ),
    children: children,
  );

  @override
  Widget builder(context, state, navigationShell) => navigationShell;
}

class BrowseExtensionBranch extends StatefulShellBranchData {
  const BrowseExtensionBranch();
  static final $initialLocation = const BrowseExtensionRoute().location;
}

class BrowseExtensionRoute extends GoRouteData with $BrowseExtensionRoute {
  const BrowseExtensionRoute();

  @override
  Widget build(context, state) => const ExtensionScreen();
}

class BrowseSourceBranch extends StatefulShellBranchData {
  const BrowseSourceBranch();
  static final $initialLocation = const BrowseSourceRoute().location;
}

class BrowseSourceRoute extends GoRouteData with $BrowseSourceRoute {
  const BrowseSourceRoute();

  @override
  Widget build(context, state) => const SourceScreen();
}

class BrowseMigrateBranch extends StatefulShellBranchData {
  const BrowseMigrateBranch();
  static final $initialLocation = const BrowseMigrateRoute().location;
}

class BrowseMigrateRoute extends GoRouteData with $BrowseMigrateRoute {
  const BrowseMigrateRoute();

  @override
  Widget build(context, state) =>
      const MigrationSourcePickerBody(hideInnerSearchOnDesktop: true);
}

class SourceTypeRoute extends GoRouteData with $SourceTypeRoute {
  const SourceTypeRoute({
    required this.sourceId,
    required this.sourceType,
    this.query,
  });
  final String sourceId;
  final SourceType sourceType;
  final String? query;

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  Widget get _screen => SourceMangaListScreen(
    key: ValueKey('$sourceId-$sourceType'),
    sourceId: sourceId,
    sourceType: sourceType,
    initialQuery: query,
  );

  @override
  Widget build(context, state) =>
      DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class SourceFilterRoute extends GoRouteData with $SourceFilterRoute {
  const SourceFilterRoute();

  @override
  Widget build(context, state) => const SourceFilterScreen();
}

class SourcePreferenceRoute extends GoRouteData with $SourcePreferenceRoute {
  const SourcePreferenceRoute({required this.sourceId});

  static final $parentNavigatorKey = _quickOpenNavigatorKey;
  final String sourceId;

  Widget get _screen => SourcePreferenceScreen(sourceId: sourceId);

  @override
  Widget build(context, state) =>
      DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}

class ExtensionInfoRoute extends GoRouteData with $ExtensionInfoRoute {
  const ExtensionInfoRoute({required this.pkgName});
  final String pkgName;
  static final $parentNavigatorKey = _quickOpenNavigatorKey;
  Widget get _screen => ExtensionInfoScreen(pkgName: pkgName);
  @override
  Widget build(context, state) => DetailNavigationShellScreen(child: _screen);
  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}
