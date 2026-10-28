// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_brand.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_title_bar.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';
import 'package:tsumiru/src/widgets/shell/desktop_sidebar.dart';
import 'package:tsumiru/src/widgets/tsumiru_logo.dart';
import 'package:window_manager/window_manager.dart';

void _mockWindowManager() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('window_manager'), (
        call,
      ) async {
        if (call.method == 'isMaximized') return false;
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null),
  );
}

List<dynamic> _overrides(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  downloadsPausedBadgeProvider.overrideWith((ref) => false),
  extensionUpdateBadgeCountProvider.overrideWith((ref) async => 0),
];

Widget _app(Widget body) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: body),
);

/// The shell frame: the bar above the sidebar, with the bar drawn only where
/// the shells draw it (desktop app in the desktop layout).
Widget _frame() => Builder(
  builder: (context) => Column(
    children: [
      if (showsMergedTopBar(context)) const DesktopTopBar(),
      Expanded(
        child: Row(
          children: [
            BigScreenNavigationBar(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
            ),
            const Expanded(child: SizedBox.expand()),
          ],
        ),
      ),
    ],
  ),
);

Future<void> _pumpFrame(
  WidgetTester tester,
  SharedPreferences prefs, {
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  _mockWindowManager();
  await tester.pumpWidget(
    ProviderScope(overrides: [..._overrides(prefs)], child: _app(_frame())),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpRoute(
  WidgetTester tester,
  Size size, {
  double slotMinWidth = 500,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  _mockWindowManager();
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        // The bar lives in the shells, inside the Navigator (under its
        // Overlay, which the tooltips need) — mirror that here.
        path: '/',
        builder: (context, state) => Scaffold(
          body: Column(
            children: [
              const DesktopTopBar(),
              Expanded(
                child: Row(
                  children: [
                    BigScreenNavigationBar(
                      selectedIndex: 0,
                      onDestinationSelected: (_) {},
                    ),
                    Expanded(
                      child: TopBarSlot(
                        minWidth: slotMinWidth,
                        content: const SizedBox(
                          height: 40,
                          child: Center(child: Text('Toolbar')),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [..._overrides(prefs)],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('catalogue keeps its toolbar after push then go', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _mockWindowManager();
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final rootKey = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: '/source',
      routes: [
        ShellRoute(
          builder: (context, state, child) => Scaffold(
            body: Column(
              children: [
                const DesktopTopBar(),
                Expanded(child: child),
              ],
            ),
          ),
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (context, state, shell) => TopBarSlot(
                minWidth: 500,
                content: const TextField(
                  decoration: InputDecoration(hintText: 'Search sources...'),
                ),
                child: shell,
              ),
              branches: [
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: '/source',
                      builder: (context, state) => const SizedBox.expand(),
                      routes: [
                        GoRoute(
                          path: ':sourceId/:sourceType',
                          parentNavigatorKey: rootKey,
                          builder: (context, state) => Scaffold(
                            body: Column(
                              children: [
                                const DesktopTopBar(),
                                Expanded(
                                  child: TopBarSlot(
                                    key: ValueKey(
                                      state.pathParameters['sourceType'],
                                    ),
                                    minWidth: 500,
                                    content: const TextField(
                                      decoration: InputDecoration(
                                        hintText: 'Search Asura Scans (EN)...',
                                      ),
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    final container = ProviderContainer(overrides: [..._overrides(prefs)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.push<void>('/source/6247824327199706550/p-o-p-u-l-a-r');
    await tester.pumpAndSettle();
    final catalogueHint = find.descendant(
      of: find.byType(DesktopTopBar),
      matching: find.text('Search Asura Scans (EN)...'),
    );
    expect(catalogueHint, findsOneWidget);
    router.go('/source/6247824327199706550/l-a-t-e-s-t');
    await tester.pumpAndSettle();
    expect(catalogueHint, findsOneWidget);
    router.go('/source/6247824327199706550/s-e-a-r-c-h?query=solo');
    await tester.pumpAndSettle();
    expect(catalogueHint, findsOneWidget);
    expect(router.canPop(), isTrue);
    router.pop();
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, '/source');
    expect(find.text('Search sources...'), findsOneWidget);
  });

  testWidgets('slot changed under a dialog shows new content after it closes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _mockWindowManager();
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final label = ValueNotifier<String>('Toolbar v1');
    addTearDown(label.dispose);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        // Slot in the shell navigator, dialog on root: the slot's own route never notifies it.
        ShellRoute(
          builder: (context, state, child) => Scaffold(
            body: Column(
              children: [
                const DesktopTopBar(),
                Expanded(child: child),
              ],
            ),
          ),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => ValueListenableBuilder<String>(
                valueListenable: label,
                builder: (context, value, _) => TopBarSlot(
                  minWidth: 500,
                  content: SizedBox(
                    height: 40,
                    child: Center(child: Text(value)),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [..._overrides(prefs)],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    Finder barText(String value) => find.descendant(
      of: find.byType(DesktopTopBar),
      matching: find.text(value),
    );
    expect(barText('Toolbar v1'), findsOneWidget);
    final barContext = tester.element(find.byType(DesktopTopBar));
    showDialog<void>(
      context: barContext,
      useRootNavigator: true,
      builder: (context) => const AlertDialog(content: Text('Cover')),
    );
    await tester.pumpAndSettle();
    label.value = 'Toolbar v2';
    await tester.pumpAndSettle();
    expect(barText('Toolbar v1'), findsOneWidget);
    expect(barText('Toolbar v2'), findsNothing);
    Navigator.of(barContext, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    expect(barText('Toolbar v2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shell toolbar stays visible under a non-opaque window route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _mockWindowManager();
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final rootKey = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: '/library',
      routes: [
        ShellRoute(
          builder: (context, state, child) => Scaffold(
            body: Column(
              children: [
                const DesktopTopBar(),
                Expanded(child: child),
              ],
            ),
          ),
          routes: [
            GoRoute(
              path: '/library',
              builder: (context, state) => TopBarSlot(
                minWidth: 500,
                content: const SizedBox(
                  height: 40,
                  child: Center(child: Text('Library toolbar')),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/upcoming',
          parentNavigatorKey: rootKey,
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            opaque: false,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) => child,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [..._overrides(prefs)],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final barText = find.descendant(
      of: find.byType(DesktopTopBar),
      matching: find.text('Library toolbar'),
    );
    expect(barText, findsOneWidget);
    router.push<void>('/upcoming');
    await tester.pumpAndSettle();
    expect(barText, findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(barText, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('merged bar, two-row fallback and macOS rail', (tester) async {
    addTearDown(() {
      debugDesktopPlatformOverride = null;
      debugAndroidOverride = null;
      debugMacOSOverride = null;
    });

    // Native desktop: one bar above the sidebar, window chrome, drag area.
    SharedPreferences.setMockInitialValues(const {});
    var prefs = await SharedPreferences.getInstance();
    await _pumpFrame(tester, prefs);
    expect(find.byType(DesktopTopBar), findsOneWidget);
    expect(find.byType(DesktopTitleBar), findsNothing);
    final barRect = tester.getRect(find.byType(DesktopTopBar));
    final sidebarRect = tester.getRect(find.byType(DesktopSidebar));
    expect(sidebarRect.top, barRect.bottom);
    expect(find.byType(WindowCaptionButton), findsNWidgets(3));
    expect(
      tester.getRect(find.byType(DragToMoveArea)),
      tester.getRect(find.byType(DesktopTopBar)),
    );

    // The brand row's logo collapses and expands the sidebar.
    await tester.tap(find.byIcon(FluentIcons.chevron_left_24_regular));
    await tester.pumpAndSettle();
    expect(find.byType(TsumiruLogo), findsOneWidget);
    await tester.tap(find.byType(TsumiruLogo));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(DesktopSidebar)).width,
      DesktopSidebar.expandedWidth,
    );
    expect(tester.takeException(), isNull);

    // A stored collapsed preference keeps the brand block inside the rail.
    await tester.pumpWidget(const SizedBox.shrink());
    SharedPreferences.setMockInitialValues(const {'sidebarExpanded': false});
    prefs = await SharedPreferences.getInstance();
    await _pumpFrame(tester, prefs);
    expect(
      tester.getSize(find.byType(DesktopSidebar)).width,
      DesktopSidebar.collapsedWidth,
    );
    final logo = find.descendant(
      of: find.byType(DesktopTopBar),
      matching: find.byType(TsumiruLogo),
    );
    expect(logo, findsOneWidget);
    final collapsedBar = tester.getRect(find.byType(DesktopTopBar));
    final logoRect = tester.getRect(logo);
    expect(logoRect.left, greaterThanOrEqualTo(collapsedBar.left));
    expect(
      logoRect.right,
      lessThanOrEqualTo(collapsedBar.left + DesktopSidebar.collapsedWidth),
    );
    expect(tester.takeException(), isNull);

    // Hosted web: the same bar, never window chrome.
    await tester.pumpWidget(const SizedBox.shrink());
    debugDesktopPlatformOverride = false;
    SharedPreferences.setMockInitialValues(const {});
    prefs = await SharedPreferences.getInstance();
    await _pumpFrame(tester, prefs);
    expect(find.byType(DesktopTopBar), findsOneWidget);
    expect(find.byType(DesktopTitleBar), findsNothing);
    expect(find.byType(DragToMoveArea), findsNothing);
    expect(find.byType(WindowCaptionButton), findsNothing);
    expect(find.byType(TsumiruLogo), findsOneWidget);
    expect(find.text('Tsumiru'), findsOneWidget);
    expect(find.byIcon(FluentIcons.chevron_left_24_regular), findsOneWidget);
    final webBar = tester.getRect(find.byType(DesktopTopBar));
    final webSidebar = tester.getRect(find.byType(DesktopSidebar));
    expect(webSidebar.top, webBar.bottom);

    // Collapse: logo-only block; expand again by tapping the logo.
    await tester.tap(find.byIcon(FluentIcons.chevron_left_24_regular));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(DesktopSidebar)).width,
      DesktopSidebar.collapsedWidth,
    );
    expect(find.text('Tsumiru'), findsNothing);
    await tester.tap(find.byType(TsumiruLogo));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(DesktopSidebar)).width,
      DesktopSidebar.expandedWidth,
    );
    expect(find.text('Tsumiru'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Android tablet at the same desktop width draws the same bar.
    await tester.pumpWidget(const SizedBox.shrink());
    debugAndroidOverride = true;
    SharedPreferences.setMockInitialValues(const {});
    prefs = await SharedPreferences.getInstance();
    await _pumpFrame(tester, prefs, size: const Size(1200, 900));
    expect(find.byType(DesktopTopBar), findsOneWidget);
    expect(find.byType(DesktopTitleBar), findsNothing);
    expect(find.byType(DragToMoveArea), findsNothing);
    expect(find.byType(WindowCaptionButton), findsNothing);
    expect(find.byType(TsumiruLogo), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Phone: no bar at all.
    await tester.pumpWidget(const SizedBox.shrink());
    debugAndroidOverride = null;
    debugDesktopPlatformOverride = null;
    SharedPreferences.setMockInitialValues(const {});
    prefs = await SharedPreferences.getInstance();
    await _pumpFrame(tester, prefs, size: const Size(412, 900));
    expect(find.byType(DesktopTopBar), findsNothing);
    expect(find.byType(DesktopTitleBar), findsNothing);
    expect(tester.takeException(), isNull);

    // Below the breakpoint the title bar and toolbar stack; the sidebar
    // starts under the toolbar row, auto-collapsed.
    SharedPreferences.setMockInitialValues(const {});
    prefs = await SharedPreferences.getInstance();
    await pumpRoute(tester, const Size(600, 900));
    final titleBar = find.byType(DesktopTitleBar);
    expect(titleBar, findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Toolbar')).dy,
      greaterThan(tester.getRect(titleBar).bottom - 1),
    );
    final stackedBar = tester.getRect(find.byType(DesktopTopBar));
    final stackedSidebar = tester.getRect(find.byType(DesktopSidebar));
    expect(stackedSidebar.top, stackedBar.bottom);
    expect(stackedSidebar.width, DesktopSidebar.collapsedWidth);
    expect(tester.takeException(), isNull);

    // Above the breakpoint the bar merges into one row.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpRoute(tester, const Size(1400, 900));
    expect(find.byType(DesktopTitleBar), findsNothing);
    expect(find.byType(DesktopTopBar), findsOneWidget);
    final mergedBar = tester.getRect(find.byType(DesktopTopBar));
    final toolbar = tester.getRect(find.text('Toolbar'));
    expect(mergedBar.contains(toolbar.topCenter), isTrue);
    expect(mergedBar.contains(toolbar.bottomCenter), isTrue);
    expect(tester.takeException(), isNull);

    // macOS falls back with no window buttons, and keeps its 80 px rail.
    await tester.pumpWidget(const SizedBox.shrink());
    debugMacOSOverride = true;
    await pumpRoute(tester, const Size(700, 900), slotMinWidth: 700);
    final macTitleBar = find.byType(DesktopTitleBar);
    expect(macTitleBar, findsOneWidget);
    expect(
      find.descendant(of: macTitleBar, matching: find.byType(TsumiruLogo)),
      findsOneWidget,
    );
    expect(find.byType(WindowCaptionButton), findsNothing);
    expect(
      tester.getTopLeft(find.text('Toolbar')).dy,
      greaterThan(tester.getRect(macTitleBar).bottom - 1),
    );
    expect(tester.takeException(), isNull);

    // The macOS expanded brand row leads the sidebar with logo, name and
    // collapse chevron, and the bar keeps only the inset.
    await tester.pumpWidget(const SizedBox.shrink());
    SharedPreferences.setMockInitialValues(const {});
    prefs = await SharedPreferences.getInstance();
    await _pumpFrame(tester, prefs);
    final sidebar = find.byType(DesktopSidebar);
    final bar = find.byType(DesktopTopBar);
    expect(tester.getSize(sidebar).width, DesktopSidebar.expandedWidth);
    expect(
      find.descendant(of: bar, matching: find.byType(TsumiruLogo)),
      findsNothing,
    );
    expect(
      find.descendant(of: bar, matching: find.byIcon(FluentIcons.chevron_left_24_regular)),
      findsNothing,
    );
    expect(
      find.descendant(of: sidebar, matching: find.byType(TsumiruLogo)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.text('Tsumiru')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.byIcon(FluentIcons.chevron_left_24_regular)),
      findsOneWidget,
    );
    expect(find.byType(DesktopBrandRow), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Collapsed, the logo alone is the sidebar's first item; tapping it
    // expands.
    await tester.pumpWidget(const SizedBox.shrink());
    SharedPreferences.setMockInitialValues(const {'sidebarExpanded': false});
    prefs = await SharedPreferences.getInstance();
    await _pumpFrame(tester, prefs);
    final collapsedSidebar = find.byType(DesktopSidebar);
    final button = find.byType(DesktopBrandExpandButton);
    expect(button, findsOneWidget);
    expect(
      find.descendant(of: collapsedSidebar, matching: find.byType(TsumiruLogo)),
      findsOneWidget,
    );
    expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNothing);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(collapsedSidebar).width,
      DesktopSidebar.expandedWidth,
    );
    expect(find.byType(DesktopBrandRow), findsOneWidget);
    expect(find.text('Tsumiru'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source toolbar replacing its loading toolbar shows on first open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _mockWindowManager();
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final rootKey = GlobalKey<NavigatorState>();
    final loaded = ValueNotifier(false);
    addTearDown(loaded.dispose);
    final buttonKey = GlobalKey();
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: '/source',
      routes: [
        ShellRoute(
          builder: (context, state, child) => Scaffold(
            body: Column(
              children: [
                const DesktopTopBar(),
                Expanded(child: child),
              ],
            ),
          ),
          routes: [
            GoRoute(
              path: '/source',
              builder: (context, state) => TopBarSlot(
                minWidth: 500,
                content: const Text('Search sources...'),
                child: const SizedBox.expand(),
              ),
              routes: [
                GoRoute(
                  path: ':sourceId',
                  parentNavigatorKey: rootKey,
                  builder: (context, state) => Scaffold(
                    body: Column(
                      children: [
                        const DesktopTopBar(),
                        Expanded(
                          child: ValueListenableBuilder(
                            valueListenable: loaded,
                            builder: (context, isLoaded, _) => isLoaded
                                ? TopBarSlot(
                                    minWidth: 500,
                                    content: LayoutBuilder(
                                      builder: (context, constraints) => Row(
                                        children: [
                                          const BackButton(),
                                          SizedBox(
                                            key: buttonKey,
                                            child: const Text('Asura Scans'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    child: const SizedBox.expand(),
                                  )
                                : titleTopBarSlot(
                                    topBar: true,
                                    leading: const BackButton(),
                                    title: const Text('Source'),
                                    child: const SizedBox.expand(),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [..._overrides(prefs)],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.push<void>('/source/1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    loaded.value = true;
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(DesktopTopBar),
        matching: find.text('Asura Scans'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
