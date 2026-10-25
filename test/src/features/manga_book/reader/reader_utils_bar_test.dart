// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Komikku-style collapsible utils bar: collapsed renders nothing tappable;
// expanded surfaces the auto-scroll toggle + interval stepper and writes
// through to the shared providers.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_utils_bar.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_webtoon_prefs/reader_webtoon_prefs.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

Future<ProviderContainer> _pumpBar(
  WidgetTester tester,
  ValueNotifier<bool> expanded,
) async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ReaderUtilsBar(
                expanded: expanded,
                readerMode: ReaderMode.webtoon,
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('interval stepper clamps to 1..30', (tester) async {
    final expanded = ValueNotifier(true);
    addTearDown(expanded.dispose);
    final container = await _pumpBar(tester, expanded);

    // Default is 3 (DBKeys.autoScrollIntervalSeconds initial).
    expect(container.read(autoScrollIntervalSecondsProvider), 3);

    await tester.tap(find.byIcon(FluentIcons.subtract_24_regular));
    await tester.pumpAndSettle();
    // 3 (fallback) - 1 = 2.
    expect(container.read(autoScrollIntervalSecondsProvider), 2);

    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byIcon(FluentIcons.add_24_regular));
      await tester.pumpAndSettle();
    }
    expect(container.read(autoScrollIntervalSecondsProvider), 12);
  });
}
