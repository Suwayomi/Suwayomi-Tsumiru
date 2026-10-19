// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/navigation_bar_data.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';
import 'package:tsumiru/src/widgets/shell/desktop_sidebar.dart';
import 'package:tsumiru/src/widgets/shell/sidebar_expanded.dart';
import 'package:tsumiru/src/widgets/tsumiru_logo.dart';

/// Pumps the desktop shell frame: the top bar above the sidebar, the way the
/// navigation shells draw them. The collapse chevron and the logo live in the
/// bar, so tests drive them from there.
Future<void> _pump(
  WidgetTester tester,
  SharedPreferences prefs, {
  Size size = const Size(1400, 900),
  int selectedIndex = 0,
  ValueChanged<int>? onDestinationSelected,
  bool downloadsPaused = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        downloadsPausedBadgeProvider.overrideWith((ref) => downloadsPaused),
        extensionUpdateBadgeCountProvider.overrideWith((ref) async => 0),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              const DesktopTopBar(),
              Expanded(
                child: Row(
                  children: [
                    BigScreenNavigationBar(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: onDestinationSelected ?? (_) {},
                    ),
                    const Expanded(child: SizedBox.expand()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BigScreenNavigationBar)))!;

double _sidebarWidth(WidgetTester tester) =>
    tester.getSize(find.byType(DesktopSidebar)).width;

void main() {
  testWidgets(
    'collapse toggles the desktop sidebar; the bar logo expands it again',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      await _pump(tester, prefs);

      // Default: expanded (labels beside icons), collapse chevron in the bar.
      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(_sidebarWidth(tester), DesktopSidebar.expandedWidth);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Collapse from the bar.
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      expect(_sidebarWidth(tester), DesktopSidebar.collapsedWidth);
      expect(
        find.byIcon(Icons.chevron_left),
        findsNothing,
        reason: 'collapsed bar shows the logo, not a chevron',
      );
      expect(
        find.byIcon(Icons.chevron_right),
        findsNothing,
        reason: 'the sidebar itself carries no toggle',
      );
      expect(
        find.byType(TsumiruLogo),
        findsOneWidget,
        reason: 'collapsed bar keeps the logo (tap to expand)',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'the narrow collapsed sidebar must not overflow',
      );

      // Expand again by tapping the bar logo.
      await tester.tap(find.byType(TsumiruLogo));
      await tester.pumpAndSettle();
      expect(_sidebarWidth(tester), DesktopSidebar.expandedWidth);
    },
  );

  testWidgets('expanded width is 208 and collapsed width is 60', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs);

    expect(_sidebarWidth(tester), 208);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), 60);
  });

  testWidgets('collapsed state persists across a rebuild', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), 60);

    // Re-pump with the SAME prefs (simulates reopening) — stays collapsed.
    await _pump(tester, prefs);
    expect(_sidebarWidth(tester), 60);
  });

  testWidgets('900x900 auto-collapses the sidebar and keeps the preference', (
    tester,
  ) async {
    // Saved preference is expanded (the default): below 1200 px the sidebar
    // still shows collapsed, without touching the stored value.
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs, size: const Size(900, 900));

    expect(find.byType(DesktopSidebar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(_sidebarWidth(tester), 60);
    // The saved preference still says expanded (the provider writes its
    // initial back on first read, so the stored value is never false here).
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DesktopSidebar)),
    );
    expect(container.read(sidebarExpandedProvider), isTrue);
    expect(prefs.getBool('sidebarExpanded'), isNot(isFalse));
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(tester.takeException(), isNull);

    // Back at 1400 px the saved preference applies again.
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), 208);
  });

  testWidgets('1400x900 shows the full desktop sidebar', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs, size: const Size(1400, 900));

    expect(find.byType(DesktopSidebar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stored collapsed pref stays collapsed at desktop width', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {'sidebarExpanded': false});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs, size: const Size(1400, 900));

    expect(_sidebarWidth(tester), 60);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed shows no label text but a tooltip with the label', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {'sidebarExpanded': false});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs);

    final l10n = _l10n(tester);
    expect(_sidebarWidth(tester), 60);
    expect(
      find.text(l10n.library),
      findsNothing,
      reason: 'collapsed rows are icon-only, no labels under icons',
    );
    expect(
      find.byWidgetPredicate((w) => w is Tooltip && w.message == l10n.library),
      findsOneWidget,
      reason: 'the label must still be available on hover',
    );

    // Expanded shows the label text.
    await tester.tap(find.byType(TsumiruLogo));
    await tester.pumpAndSettle();
    expect(find.text(l10n.library), findsOneWidget);
  });

  testWidgets('selected row uses the primary colour', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs, selectedIndex: 2);

    final l10n = _l10n(tester);
    final context = tester.element(find.byType(DesktopSidebar));
    final primary = Theme.of(context).colorScheme.primary;

    final selectedText = tester.widget<Text>(find.text(l10n.history));
    expect(selectedText.style?.color, primary);

    final unselectedText = tester.widget<Text>(find.text(l10n.library));
    expect(unselectedText.style?.color, isNot(primary));
  });

  testWidgets('tapping a row calls onDestinationSelected with its index', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final tapped = <int>[];
    await _pump(tester, prefs, onDestinationSelected: tapped.add);

    final l10n = _l10n(tester);
    await tester.tap(find.text(l10n.browse));
    await tester.pumpAndSettle();
    expect(tapped, [
      3,
    ], reason: 'desktop nav list is the tablet list (History sits at 2)');
  });

  testWidgets('each row exposes its label exactly once to screen readers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final handle = tester.ensureSemantics();
    await _pump(tester, prefs);

    final l10n = _l10n(tester);
    Finder libraryRow() => find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == l10n.library,
    );

    // Expanded: visible text is excluded, so the explicit label is the
    // only name (otherwise a reader announces "Library\nLibrary").
    expect(find.text(l10n.library), findsOneWidget);
    expect(libraryRow(), findsOneWidget);
    expect(
      tester.getSemantics(libraryRow()),
      matchesSemantics(
        label: l10n.library,
        isButton: true,
        isFocusable: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    // Collapsed: icon-only row keeps the explicit label.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text(l10n.library), findsNothing);
    expect(libraryRow(), findsOneWidget);
    expect(
      tester.getSemantics(libraryRow()),
      matchesSemantics(
        label: l10n.library,
        isButton: true,
        isFocusable: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('collapsed rows are 44px tall with 6px gaps', (tester) async {
    SharedPreferences.setMockInitialValues(const {'sidebarExpanded': false});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs);
    expect(_sidebarWidth(tester), 60);

    final rows = find.descendant(
      of: find.byType(DesktopSidebar),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxHeight == 44,
      ),
    );
    expect(rows, findsNWidgets(6));
    expect(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.constraints?.maxHeight == 40,
        ),
      ),
      findsNothing,
    );

    final tops = [
      for (var i = 0; i < 6; i++) tester.getTopLeft(rows.at(i)).dy,
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(
        tops[i] - tops[i - 1],
        50,
        reason: 'collapsed pitch is 44px row + 6px gap',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded rows stay 40px tall with 2px gaps', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs);
    expect(_sidebarWidth(tester), 208);

    final rows = find.descendant(
      of: find.byType(DesktopSidebar),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxHeight == 40,
      ),
    );
    expect(rows, findsNWidgets(6));
    expect(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.constraints?.maxHeight == 44,
        ),
      ),
      findsNothing,
    );

    final tops = [
      for (var i = 0; i < 6; i++) tester.getTopLeft(rows.at(i)).dy,
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(
        tops[i] - tops[i - 1],
        42,
        reason: 'expanded pitch is 40px row + 2px gap',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('1400x600 collapsed shows all six destinations', (tester) async {
    SharedPreferences.setMockInitialValues(const {'sidebarExpanded': false});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs, size: const Size(1400, 600));

    final context = tester.element(find.byType(DesktopSidebar));
    final navList = NavigationBarData.getNavList(context);
    expect(navList, hasLength(6));

    for (final data in navList) {
      final label = data.label(context);
      final row = find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == label,
      );
      expect(row, findsOneWidget, reason: 'collapsed row keeps "$label"');
      final rect = tester.getRect(row);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(600));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('badges still render on the sidebar icons', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs, downloadsPaused: true);

    // Paused downloads with work waiting badges the Downloads tab.
    expect(find.byType(Badge), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
