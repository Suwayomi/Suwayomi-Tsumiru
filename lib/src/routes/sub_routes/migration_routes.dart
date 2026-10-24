part of '../router_config.dart';

class MigrationGlobalSearchRoute extends GoRouteData
    with $MigrationGlobalSearchRoute {
  const MigrationGlobalSearchRoute({this.$extra});

  final MigrationRouteData? $extra;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final extra = $extra;
    if (extra == null) return const _MigrationDataUnavailable();
    return MigrationGlobalSearchScreen(sourceManga: extra.sourceManga);
  }
}

class MigrationSourcePickerRoute extends GoRouteData
    with $MigrationSourcePickerRoute {
  const MigrationSourcePickerRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const MigrationSourcePickerScreen();
}

class MigrationSourceMangaRoute extends GoRouteData
    with $MigrationSourceMangaRoute {
  const MigrationSourceMangaRoute({this.$extra});

  final MigrationSourceMangaData? $extra;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final extra = $extra;
    if (extra == null) return const _MigrationDataUnavailable();
    return MigrationSourceMangaScreen(data: extra);
  }
}

class MigrationBulkConfigRoute extends GoRouteData
    with $MigrationBulkConfigRoute {
  const MigrationBulkConfigRoute({this.$extra});

  final MigrationBulkConfigData? $extra;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final extra = $extra;
    if (extra == null || extra.mangaIds.isEmpty) {
      return const _MigrationDataUnavailable();
    }
    return MigrationBulkConfigScreen(mangaIds: extra.mangaIds);
  }
}

class MigrationBulkRunRoute extends GoRouteData with $MigrationBulkRunRoute {
  const MigrationBulkRunRoute({this.$extra});

  final MigrationBulkRunData? $extra;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final extra = $extra;
    if (extra == null || extra.mangaIds.isEmpty) {
      return const _MigrationDataUnavailable();
    }
    return MigrationBulkRunScreen(data: extra);
  }
}

/// URL restoration cannot serialize migration extras; show a fallback when they are missing.
class _MigrationDataUnavailable extends StatelessWidget {
  const _MigrationDataUnavailable();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.migrationDataUnavailable,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  final router = GoRouter.of(context);
                  if (router.canPop()) {
                    router.pop();
                  } else {
                    const LibraryRoute(categoryId: 0).go(context);
                  }
                },
                child: Text(context.l10n.back),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
