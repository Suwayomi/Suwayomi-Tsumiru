// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
      if (useDesktopTopBar(context)) const DesktopTopBar(),
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

void main() {
  test('breakpoint is built from the actual part widths', () {
    // Brand block + gap + slot + gap + window buttons + gap.
    expect(
      topBarBreakpoint(
        brandWidth: 208,
        slotMinWidth: 500,
        isMacOS: false,
      ),
      208 + 10 + 500 + 10 + 3 * 46 + 10,
    );
    // macOS draws no window buttons.
    expect(
      topBarBreakpoint(
        brandWidth: 208,
        slotMinWidth: 500,
        isMacOS: true,
      ),
      208 + 10 + 500 + 10,
    );
  });

  testWidgets('1400x900 draws one 64 px bar above the sidebar', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await _pumpFrame(tester, prefs);

    expect(find.byType(DesktopTopBar), findsOneWidget);
    expect(tester.getSize(find.byType(DesktopTopBar)).height, 64);
    expect(find.byType(DesktopTitleBar), findsNothing);

    final barRect = tester.getRect(find.byType(DesktopTopBar));
    final sidebarRect = tester.getRect(find.byType(DesktopSidebar));
    expect(sidebarRect.top, barRect.bottom);
    expect(sidebarRect.width, 208);

    expect(find.byType(WindowCaptionButton), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed brand block matches the 60 px sidebar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {'sidebarExpanded': false});
    final prefs = await SharedPreferences.getInstance();
    await _pumpFrame(tester, prefs);

    expect(tester.getSize(find.byType(DesktopSidebar)).width, 60);
    final logo = find.descendant(
      of: find.byType(DesktopTopBar),
      matching: find.byType(TsumiruLogo),
    );
    expect(logo, findsOneWidget);
    final logoRect = tester.getRect(logo);
    final barRect = tester.getRect(find.byType(DesktopTopBar));
    expect(logoRect.left, greaterThanOrEqualTo(barRect.left));
    expect(logoRect.right, lessThanOrEqualTo(barRect.left + 60));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a DragToMoveArea covers the bar behind the controls', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {'sidebarExpanded': false});
    final prefs = await SharedPreferences.getInstance();
    await _pumpFrame(tester, prefs);

    expect(
      tester.getRect(find.byType(DragToMoveArea)),
      tester.getRect(find.byType(DesktopTopBar)),
    );

    // Tapping the logo still reaches the control above the drag area.
    await tester.tap(find.byType(TsumiruLogo));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DesktopSidebar)).width, 208);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone size draws no top bar', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await _pumpFrame(tester, prefs, size: const Size(412, 900));

    expect(find.byType(DesktopTopBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('macOS', () {
    setUp(() => debugMacOSOverride = true);
    tearDown(() => debugMacOSOverride = null);

    testWidgets('expanded bar holds the inset and the chevron, no logo', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      await _pumpFrame(tester, prefs);

      expect(tester.getSize(find.byType(DesktopSidebar)).width, 208);
      expect(find.byType(TsumiruLogo), findsNothing);
      expect(find.byType(WindowCaptionButton), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('collapsed sidebar is 80 px with the chevron at its bottom', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(const {'sidebarExpanded': false});
      final prefs = await SharedPreferences.getInstance();
      await _pumpFrame(tester, prefs);

      expect(tester.getSize(find.byType(DesktopSidebar)).width, 80);
      expect(find.byType(TsumiruLogo), findsNothing);
      expect(find.byType(WindowCaptionButton), findsNothing);
      final expand = find.byIcon(Icons.chevron_right);
      expect(expand, findsOneWidget);
      final sidebarRect = tester.getRect(find.byType(DesktopSidebar));
      expect(
        tester.getRect(expand).bottom,
        lessThanOrEqualTo(sidebarRect.bottom),
      );

      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(DesktopSidebar)).width, 208);
      expect(tester.takeException(), isNull);
    });
  });

  group('two-row fallback', () {
    late SharedPreferences prefs;
    late GoRouter router;

    Future<void> pumpRoute(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _mockWindowManager();
      SharedPreferences.setMockInitialValues(const {});
      prefs = await SharedPreferences.getInstance();
      router = GoRouter(
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
                    child: TopBarSlot(
                      minWidth: 500,
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

    testWidgets('below the breakpoint the title bar and toolbar stack', (
      tester,
    ) async {
      // 208 + 10 + 500 + 10 + 138 + 10 = 886, so 600 px falls back.
      await pumpRoute(tester, const Size(600, 900));

      final titleBar = find.byType(DesktopTitleBar);
      expect(titleBar, findsOneWidget);
      expect(tester.getSize(titleBar).height, 40);
      expect(
        tester.getTopLeft(find.text('Toolbar')).dy,
        greaterThan(tester.getRect(titleBar).bottom - 1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('above the breakpoint the bar merges into one row', (
      tester,
    ) async {
      await pumpRoute(tester, const Size(1400, 900));

      expect(find.byType(DesktopTitleBar), findsNothing);
      expect(find.byType(DesktopTopBar), findsOneWidget);
      final barRect = tester.getRect(find.byType(DesktopTopBar));
      final toolbarRect = tester.getRect(find.text('Toolbar'));
      expect(barRect.contains(toolbarRect.topCenter), isTrue);
      expect(barRect.contains(toolbarRect.bottomCenter), isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
