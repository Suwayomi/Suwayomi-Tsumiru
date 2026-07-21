part of '../router_config.dart';

class MigrationGlobalSearchRoute extends GoRouteData with $MigrationGlobalSearchRoute {
  const MigrationGlobalSearchRoute({this.$extra});

  static final $parentNavigatorKey = _quickOpenNavigatorKey;
  final MigrationRouteData? $extra;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    if ($extra == null) {
      // If no manga provided, navigate back
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.pop();
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return MigrationGlobalSearchScreen(sourceManga: $extra!.sourceManga);
  }
}

class MigrationSourcePickerRoute extends GoRouteData
    with $MigrationSourcePickerRoute {
  const MigrationSourcePickerRoute();

  static final $parentNavigatorKey = _quickOpenNavigatorKey;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const MigrationSourcePickerScreen();
}

class MigrationSourceMangaRoute extends GoRouteData
    with $MigrationSourceMangaRoute {
  const MigrationSourceMangaRoute({this.$extra});

  static final $parentNavigatorKey = _quickOpenNavigatorKey;
  final MigrationSourceMangaData? $extra;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final extra = $extra;
    if (extra == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.pop());
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return MigrationSourceMangaScreen(data: extra);
  }
}

class MigrationBulkConfigRoute extends GoRouteData with $MigrationBulkConfigRoute {
  const MigrationBulkConfigRoute({this.$extra});

  static final $parentNavigatorKey = _quickOpenNavigatorKey;
  final MigrationBulkConfigData? $extra;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final extra = $extra;
    if (extra == null || extra.mangaIds.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.pop());
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return MigrationBulkConfigScreen(mangaIds: extra.mangaIds);
  }
}

class MigrationBulkRunRoute extends GoRouteData with $MigrationBulkRunRoute {
  const MigrationBulkRunRoute({this.$extra});

  static final $parentNavigatorKey = _quickOpenNavigatorKey;
  final MigrationBulkRunData? $extra;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final extra = $extra;
    if (extra == null || extra.mangaIds.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.pop());
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return MigrationBulkRunScreen(data: extra);
  }
}

