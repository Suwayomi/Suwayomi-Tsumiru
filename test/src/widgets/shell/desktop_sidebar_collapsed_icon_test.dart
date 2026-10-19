// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Collapsed (60 px) rows must not squash their icons: with 8 px sidebar
// padding a row is 44 px wide, and the expanded layout's 12 px horizontal row
// padding left only 20 px for a 24 px icon, drawing circles as tall ovals.

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
import 'package:tsumiru/src/widgets/shell/animated_nav_icon.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';
import 'package:tsumiru/src/widgets/shell/desktop_sidebar.dart';
import 'package:tsumiru/src/widgets/tsumiru_logo.dart';

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

Future<void> _pumpCollapsed(
  WidgetTester tester,
  SharedPreferences prefs, {
  bool downloadsPaused = false,
  int extensionUpdates = 0,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        downloadsPausedBadgeProvider.overrideWith((ref) => downloadsPaused),
        extensionUpdateBadgeCountProvider.overrideWith(
          (ref) async => extensionUpdates,
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            children: [
              BigScreenNavigationBar(
                selectedIndex: 0,
                onDestinationSelected: (_) {},
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

Finder _rowContainers(double height) => find.descendant(
  of: find.byType(DesktopSidebar),
  matching: find.byWidgetPredicate(
    (w) => w is Container && w.constraints?.maxHeight == height,
  ),
);

void main() {
  testWidgets('collapsed icons render square at their natural size', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {'sidebarExpanded': false});
    final prefs = await SharedPreferences.getInstance();
    await _pumpCollapsed(tester, prefs);
    expect(tester.getSize(find.byType(DesktopSidebar)).width, 60);

    final icons = find.descendant(
      of: find.byType(DesktopSidebar),
      matching: find.byType(AnimatedNavIcon),
    );
    expect(icons, findsNWidgets(6));
    for (var i = 0; i < 6; i++) {
      expect(
        tester.getSize(icons.at(i)),
        const Size(24, 24),
        reason: 'collapsed destination icon $i must not be squashed',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('badges do not change the collapsed icon size', (tester) async {
    SharedPreferences.setMockInitialValues(const {'sidebarExpanded': false});
    final prefs = await SharedPreferences.getInstance();
    await _pumpCollapsed(
      tester,
      prefs,
      downloadsPaused: true,
      extensionUpdates: 3,
    );
    expect(find.byType(Badge), findsWidgets);

    final icons = find.descendant(
      of: find.byType(DesktopSidebar),
      matching: find.byType(AnimatedNavIcon),
    );
    expect(icons, findsNWidgets(6));
    for (var i = 0; i < 6; i++) {
      expect(
        tester.getSize(icons.at(i)),
        const Size(24, 24),
        reason: 'badged collapsed destination icon $i must stay 24x24',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed rows carry no horizontal padding', (tester) async {
    SharedPreferences.setMockInitialValues(const {'sidebarExpanded': false});
    final prefs = await SharedPreferences.getInstance();
    await _pumpCollapsed(tester, prefs);

    final rows = _rowContainers(44);
    expect(rows, findsNWidgets(6));
    for (var i = 0; i < 6; i++) {
      final padding = tester.widget<Container>(rows.at(i)).padding;
      expect(
        padding,
        isNot(
          const EdgeInsets.symmetric(horizontal: 12),
        ),
        reason: 'collapsed row $i must not keep the expanded 12 px padding',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded rows keep their 12 px horizontal padding', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await _pumpCollapsed(tester, prefs);
    // Default pref is expanded.
    expect(tester.getSize(find.byType(DesktopSidebar)).width, 208);

    final rows = _rowContainers(40);
    expect(rows, findsNWidgets(6));
    for (var i = 0; i < 6; i++) {
      expect(
        tester.widget<Container>(rows.at(i)).padding,
        const EdgeInsets.symmetric(horizontal: 12),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed bar logo renders square at 28 px', (tester) async {
    SharedPreferences.setMockInitialValues(const {'sidebarExpanded': false});
    final prefs = await SharedPreferences.getInstance();
    _mockWindowManager();
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The logo header moved to the top bar above the sidebar.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          downloadsPausedBadgeProvider.overrideWith((ref) => false),
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
                        selectedIndex: 0,
                        onDestinationSelected: (_) {},
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

    expect(tester.getSize(find.byType(DesktopSidebar)).width, 60);
    expect(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.byType(TsumiruLogo),
      ),
      findsNothing,
      reason: 'the sidebar carries no header of its own anymore',
    );
    final logo = find.descendant(
      of: find.byType(DesktopTopBar),
      matching: find.byType(TsumiruLogo),
    );
    expect(logo, findsOneWidget);
    expect(tester.getSize(logo), const Size(28, 28));
    expect(tester.takeException(), isNull);
  });
}
