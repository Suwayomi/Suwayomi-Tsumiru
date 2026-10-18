import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';
import 'package:tsumiru/src/widgets/shell/desktop_sidebar.dart';

GoRouter _router(String location) {
  final quickSearch = $appRoutes.whereType<ShellRoute>().first;
  final details = quickSearch.routes.whereType<ShellRoute>().first;
  final manga = details.routes.whereType<GoRoute>().firstWhere(
    (route) => route.path == Routes.mangaRoute,
  );
  final reader = manga.routes.single as GoRoute;
  return GoRouter(
    initialLocation: location,
    routes: [
      ShellRoute(
        navigatorKey: quickSearch.navigatorKey,
        builder: (context, state, child) => child,
        routes: [
          ShellRoute(
            navigatorKey: details.navigatorKey,
            builder: details.builder,
            routes: [
              ...details.routes.where((route) => route != manga),
              GoRoute(
                path: manga.path,
                builder: (_, _) => const Scaffold(body: Text('Series')),
                routes: [
                  GoRoute(
                    path: reader.path,
                    parentNavigatorKey: reader.parentNavigatorKey,
                    builder: (_, _) => const Scaffold(body: Text('Reader')),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<GoRouter> _pump(
  WidgetTester tester,
  Size size,
  String location, [
  Map<String, Object> initialPrefs = const {},
]) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  final router = _router(location);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        downloadsPausedBadgeProvider.overrideWith((ref) => false),
        extensionUpdateBadgeCountProvider.overrideWith((ref) async => 0),
        failedUpdatesProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  for (final size in [
    const Size(1400, 900),
    const Size(800, 900),
    const Size(400, 800),
  ]) {
    testWidgets('update errors navigation at ${size.width}px', (tester) async {
      await _pump(tester, size, const LibraryUpdateErrorsRoute().location);
      expect(
        find.byType(BigScreenNavigationBar),
        size.width >= 600 ? findsOneWidget : findsNothing,
      );
      if (size.width >= 1200) {
        // Desktop uses the custom sidebar, not a NavigationRail.
        expect(find.byType(NavigationRail), findsNothing);
        final sidebar = tester.widget<DesktopSidebar>(
          find.byType(DesktopSidebar),
        );
        expect(
          tester.getSize(find.byType(DesktopSidebar)).width,
          DesktopSidebar.expandedWidth,
        );
        expect(sidebar.selectedIndex, 0);
      } else if (size.width >= 600) {
        final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
        expect(rail.extended, isFalse);
        expect(rail.selectedIndex, 0);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('detail shell follows the sidebar preference at desktop width', (
    tester,
  ) async {
    await _pump(
      tester,
      const Size(1400, 900),
      const LibraryUpdateErrorsRoute().location,
    );
    expect(
      tester.getSize(find.byType(DesktopSidebar)).width,
      DesktopSidebar.expandedWidth,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail shell collapses when the sidebar preference is off', (
    tester,
  ) async {
    await _pump(
      tester,
      const Size(1400, 900),
      const LibraryUpdateErrorsRoute().location,
      const {'sidebarExpanded': false},
    );
    expect(
      tester.getSize(find.byType(DesktopSidebar)).width,
      DesktopSidebar.collapsedWidth,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail shell shows the icon rail at tablet width', (
    tester,
  ) async {
    await _pump(
      tester,
      const Size(800, 900),
      const LibraryUpdateErrorsRoute().location,
    );
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reader covers the rail and back returns to series', (
    tester,
  ) async {
    final router = await _pump(
      tester,
      const Size(1400, 900),
      const MangaRoute(mangaId: 1).location,
    );
    expect(find.byType(BigScreenNavigationBar), findsOneWidget);
    router.push(const ReaderRoute(mangaId: 1, chapterId: 2).location);
    await tester.pumpAndSettle();
    expect(find.text('Reader'), findsOneWidget);
    expect(find.byType(BigScreenNavigationBar), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Series'), findsOneWidget);
    expect(find.byType(BigScreenNavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
