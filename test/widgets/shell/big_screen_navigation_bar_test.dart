// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';
import 'package:tsumiru/src/widgets/shell/desktop_sidebar.dart';
import 'package:tsumiru/src/widgets/tsumiru_logo.dart';

Future<void> _pump(
  WidgetTester tester,
  SharedPreferences prefs, {
  Size size = const Size(1400, 900),
  int selectedIndex = 0,
  ValueChanged<int>? onDestinationSelected,
  bool downloadsPaused = false,
}) async {
  // Default width (>= 1200) is desktop, so the custom sidebar + collapse
  // toggle show; callers pass a narrower size to exercise the tablet rail.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        downloadsPausedBadgeProvider.overrideWith((ref) => downloadsPaused),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            children: [
              BigScreenNavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected ?? (_) {},
              ),
              const Expanded(child: SizedBox.expand()),
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
    'collapse toggles the desktop sidebar; the logo stays as expand',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      await _pump(tester, prefs);

      // Default: expanded (labels beside icons), collapse chevron shown.
      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(_sidebarWidth(tester), DesktopSidebar.expandedWidth);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Collapse.
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      expect(_sidebarWidth(tester), DesktopSidebar.collapsedWidth);
      expect(
        find.byIcon(Icons.chevron_right),
        findsNothing,
        reason: 'the header must not swap to a chevron when collapsed',
      );
      expect(
        find.byType(TsumiruLogo),
        findsOneWidget,
        reason: 'collapsed sidebar keeps the logo (tap to expand)',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'the narrow collapsed sidebar must not overflow',
      );

      // Expand again by tapping the logo.
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

  testWidgets('tablet width ignores the collapse pref (no stranded chevron)', (
    tester,
  ) async {
    // Persist "collapsed", then render at tablet width (600–1199).
    SharedPreferences.setMockInitialValues(const {'sidebarExpanded': false});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs, size: const Size(900, 1200));

    // Tablet rail: the custom sidebar never shows, and no collapse/expand
    // chevron — just the normal icon rail (the desktop-only toggle must not
    // leak here).
    expect(find.byType(DesktopSidebar), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
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

  testWidgets('badges still render on the sidebar icons', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs, downloadsPaused: true);

    // Paused downloads with work waiting badges the Downloads tab.
    expect(find.byType(Badge), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
