part of '../router_config.dart';

class DownloadsBranch extends StatefulShellBranchData {
  const DownloadsBranch();
}

class DownloadsRoute extends GoRouteData with $DownloadsRoute {
  const DownloadsRoute();
  @override
  Widget build(context, state) => const DownloadsScreen();
}
