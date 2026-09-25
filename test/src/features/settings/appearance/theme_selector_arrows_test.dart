// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/settings/presentation/appearance/widgets/app_theme_selector/app_theme_selector.dart';
import 'package:tsumiru/src/features/settings/widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

Finder _arrow(IconData icon) => find.widgetWithIcon(IconButton, icon);

Future<void> _pumpSelector(WidgetTester tester, {required Size size}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ThemeSelector(title: Text('Themes')),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a 412px row starts on the left arrow disabled', (tester) async {
    await _pumpSelector(tester, size: const Size(412, 800));

    final previous = _arrow(Icons.chevron_left_rounded);
    final next = _arrow(Icons.chevron_right_rounded);
    expect(previous, findsOneWidget);
    expect(next, findsOneWidget);
    expect(tester.widget<IconButton>(previous).onPressed, isNull);
    expect(tester.widget<IconButton>(next).onPressed, isNotNull);
  });

  testWidgets('the right arrow scrolls the row and re-enables the left one', (
    tester,
  ) async {
    await _pumpSelector(tester, size: const Size(412, 800));

    await tester.tap(_arrow(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.pixels, greaterThan(0));
    expect(
      tester.widget<IconButton>(_arrow(Icons.chevron_left_rounded)).onPressed,
      isNotNull,
    );
  });

  testWidgets('a row with nothing to scroll shows no arrows', (tester) async {
    await _pumpSelector(tester, size: const Size(3000, 800));

    expect(_arrow(Icons.chevron_left_rounded), findsNothing);
    expect(_arrow(Icons.chevron_right_rounded), findsNothing);
  });

  test('with no stored mode the app follows the system', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    expect(DBKeys.themeMode.initial, ThemeMode.system);
    expect(container.read(appThemeModeProvider), ThemeMode.system);
  });
}
