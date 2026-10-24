part of '../router_config.dart';

class HistoryBranch extends StatefulShellBranchData {
  const HistoryBranch();
  static final $initialLocation = const HistoryTabRoute().location;
}

class HistoryTabRoute extends GoRouteData with $HistoryTabRoute {
  const HistoryTabRoute();
  @override
  Widget build(context, state) => const HistoryScreen();
}

// Push phone History full-screen so it is not retained inside the More branch.
class HistoryRoute extends GoRouteData with $HistoryRoute {
  const HistoryRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  Widget get _screen => const HistoryScreen();

  @override
  Widget build(context, state) =>
      DetailNavigationShellScreen(child: _screen);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      detailNavigationPage(context, state, _screen);
}
