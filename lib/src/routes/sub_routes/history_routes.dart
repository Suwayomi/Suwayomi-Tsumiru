part of '../router_config.dart';

// History Branch for tablet navigation
class HistoryBranch extends StatefulShellBranchData {
  const HistoryBranch();
  static final $initialLocation = const HistoryTabRoute().location;
}

// History route for tablet navigation tab
class HistoryTabRoute extends GoRouteData with $HistoryTabRoute {
  const HistoryTabRoute();
  @override
  Widget build(context, state) => const HistoryScreen();
}

// History route for phone navigation (under More). Full screen and pushed,
// like every other More entry: left inside the More tab, it stayed stacked
// there after switching tabs, and Back on the library tab then exited nothing.
class HistoryRoute extends GoRouteData with $HistoryRoute {
  const HistoryRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(context, state) => const HistoryScreen();
}
