// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  testWidgets('collapse, auto-collapse and accessible labels', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs);

    // Default: expanded (labels beside icons), collapse chevron in the bar.
    expect(find.byType(DesktopSidebar), findsOneWidget);
    expect(_sidebarWidth(tester), DesktopSidebar.expandedWidth);
    expect(find.byIcon(FluentIcons.panel_left_24_regular), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Collapse from the bar.
    await tester.tap(find.byIcon(FluentIcons.panel_left_24_regular));
    await tester.pumpAndSettle();

    expect(_sidebarWidth(tester), DesktopSidebar.collapsedWidth);
    expect(
      find.byIcon(FluentIcons.panel_left_24_regular),
      findsOneWidget,
    );
    expect(
      find.byIcon(FluentIcons.chevron_right_24_regular),
      findsNothing,
      reason: 'the sidebar itself carries no toggle',
    );
    expect(
      find.byType(TsumiruLogo),
      findsNothing,
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'the narrow collapsed sidebar must not overflow',
    );

    await tester.tap(find.byIcon(FluentIcons.panel_left_24_regular));
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), DesktopSidebar.expandedWidth);

    // Collapsed state persists across a rebuild.
    await tester.tap(find.byIcon(FluentIcons.panel_left_24_regular));
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), DesktopSidebar.collapsedWidth);
    await _pump(tester, prefs);
    expect(_sidebarWidth(tester), DesktopSidebar.collapsedWidth);

    // 900x900 auto-collapses the sidebar and keeps the preference: the saved
    // preference is expanded (the default), but below 1008 px the sidebar
    // still shows collapsed without touching the stored value.
    await tester.pumpWidget(const SizedBox.shrink());
    SharedPreferences.setMockInitialValues(const {});
    final narrowPrefs = await SharedPreferences.getInstance();
    await _pump(tester, narrowPrefs, size: const Size(900, 900));

    expect(find.byType(DesktopSidebar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(_sidebarWidth(tester), 60);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DesktopSidebar)),
    );
    expect(container.read(sidebarExpandedProvider), isTrue);
    expect(narrowPrefs.getBool('sidebarExpanded'), isNot(isFalse));
    expect(find.byIcon(FluentIcons.panel_left_24_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNothing);
    expect(tester.takeException(), isNull);

    // Back at 1400 px the saved preference applies again.
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), 208);

    // Each row exposes its label exactly once to screen readers.
    await tester.pumpWidget(const SizedBox.shrink());
    SharedPreferences.setMockInitialValues(const {});
    final semanticPrefs = await SharedPreferences.getInstance();
    final handle = tester.ensureSemantics();
    await _pump(tester, semanticPrefs);

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
    await tester.tap(find.byIcon(FluentIcons.panel_left_24_regular));
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
}
