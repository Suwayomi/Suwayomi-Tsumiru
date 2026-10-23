// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Desktop sidebar foot: Incognito and Settings sit below the destinations,
// while narrower sidebars keep More.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/features/settings/presentation/incognito/incognito_mode.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';
import 'package:tsumiru/src/widgets/shell/desktop_sidebar.dart';

void main() {
  testWidgets('desktop sidebar foot shows Incognito and Settings, no More', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
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

    final l10n = AppLocalizations.of(
      tester.element(find.byType(BigScreenNavigationBar)),
    )!;
    expect(find.byType(DesktopSidebar), findsOneWidget);
    for (final label in [
      l10n.library,
      l10n.updates,
      l10n.history,
      l10n.browse,
      l10n.downloads,
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text(l10n.more), findsNothing);
    expect(find.text(l10n.incognitoShort), findsOneWidget);
    expect(find.text(l10n.settings), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    // The foot switch drives the same provider as the More screen's switch.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DesktopSidebar)),
    );
    expect(container.read(incognitoModeProvider), isFalse);
    await tester.tap(find.text(l10n.incognitoShort));
    await tester.pumpAndSettle();
    expect(container.read(incognitoModeProvider), isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    tester.view.physicalSize = const Size(700, 900);
    await tester.pumpAndSettle();
    expect(find.byTooltip(l10n.more), findsOneWidget);
    expect(find.byTooltip(l10n.incognitoShort), findsNothing);
    expect(find.byTooltip(l10n.settings), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
