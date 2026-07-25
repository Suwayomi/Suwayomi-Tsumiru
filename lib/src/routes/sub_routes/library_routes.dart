part of '../router_config.dart';

// Library Branch
class LibraryBranch extends StatefulShellBranchData {
  static final $initialLocation = const LibraryRoute(categoryId: 0).location;
  const LibraryBranch();
}

class LibraryRoute extends GoRouteData with $LibraryRoute {
  const LibraryRoute({required this.categoryId});
  final int categoryId;
  @override
  Widget build(context, state) => LibraryScreen(categoryId: categoryId);
}

class LibraryDuplicatesRoute extends GoRouteData with $LibraryDuplicatesRoute {
  const LibraryDuplicatesRoute();
  @override
  Widget build(context, state) => const LibraryDuplicatesScreen();
}
