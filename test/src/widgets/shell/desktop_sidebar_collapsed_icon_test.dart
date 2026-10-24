// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Collapsed (60 px) rows must not squash their icons: with 8 px sidebar
// padding a row is 44 px wide, and the expanded layout's 12 px horizontal row
// padding left only 20 px for a 24 px icon, drawing circles as tall ovals.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/navigation_bar_data.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';
import 'package:tsumiru/src/widgets/shell/desktop_sidebar.dart';

Future<void> _pumpCollapsed(
  WidgetTester tester,
  SharedPreferences prefs,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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

    final navIcons = {
      for (final d in NavigationBarData.desktopNavList)
        ...[d.icon, d.activeIcon],
    };
    final icons = find.descendant(
      of: find.byType(DesktopSidebar),
      matching: find.byWidgetPredicate(
        (w) => w is Icon && navIcons.contains(w.icon),
      ),
    );
    // Five destinations: More left the desktop sidebar for the foot below.
    expect(icons, findsNWidgets(5));
    // The selected destination settles on its filled glyph.
    expect(
      find.byIcon(NavigationBarData.desktopNavList[0].activeIcon),
      findsOneWidget,
    );
    expect(
      find.byIcon(NavigationBarData.desktopNavList[0].icon),
      findsNothing,
    );
    for (var i = 0; i < 5; i++) {
      expect(
        tester.getSize(icons.at(i)),
        const Size(24, 24),
        reason: 'collapsed destination icon $i must not be squashed',
      );
    }
    // Collapsed rows carry none of the expanded layout's 12 px padding:
    // five destinations plus the Incognito and Settings foot rows.
    final rows = _rowContainers(44);
    expect(rows, findsNWidgets(7));
    for (var i = 0; i < 7; i++) {
      expect(
        tester.widget<Container>(rows.at(i)).padding,
        isNot(const EdgeInsets.symmetric(horizontal: 12)),
        reason: 'collapsed row $i must not keep the expanded 12 px padding',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
