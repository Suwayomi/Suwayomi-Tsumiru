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

Future<void> _pump(WidgetTester tester, SharedPreferences prefs,
    {Size size = const Size(1400, 900)}) async {
  // Default width (>= 1200) is desktop, so the extended rail + collapse toggle
  // show; callers pass a narrower size to exercise the tablet rail.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        downloadsPausedBadgeProvider.overrideWith((ref) => false),
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

NavigationRail _rail(WidgetTester tester) =>
    tester.widget<NavigationRail>(find.byType(NavigationRail));

void main() {
  testWidgets('collapse chevron toggles the desktop rail to an icon rail',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs);

    // Default: expanded (labels beside icons), collapse chevron shown.
    expect(_rail(tester).extended, isTrue);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Collapse.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(_rail(tester).extended, isFalse,
        reason: 'tapping collapse must switch to the icon-only rail');
    expect(find.byIcon(Icons.chevron_right), findsOneWidget,
        reason: 'collapsed rail shows an expand chevron');
    expect(tester.takeException(), isNull,
        reason: 'the narrow collapsed leading must not overflow');

    // Expand again.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(_rail(tester).extended, isTrue);
  });

  testWidgets('collapsed state persists across a rebuild', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(_rail(tester).extended, isFalse);

    // Re-pump with the SAME prefs (simulates reopening) — stays collapsed.
    await _pump(tester, prefs);
    expect(_rail(tester).extended, isFalse);
  });

  testWidgets('tablet width ignores the collapse pref (no stranded chevron)',
      (tester) async {
    // Persist "collapsed", then render at tablet width (600–1199).
    SharedPreferences.setMockInitialValues(
        const {'sidebarExpanded': false});
    final prefs = await SharedPreferences.getInstance();
    await _pump(tester, prefs, size: const Size(900, 1200));

    // Tablet rail: never extended, and no collapse/expand chevron — just the
    // normal icon rail (the desktop-only toggle must not leak here).
    expect(_rail(tester).extended, isFalse);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
