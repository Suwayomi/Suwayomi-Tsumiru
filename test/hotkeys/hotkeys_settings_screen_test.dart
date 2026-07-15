// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/hotkeys/presentation/hotkeys_settings_screen.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('lists Global and Reader sections', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HotkeysSettingsScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Global'), findsOneWidget);
    expect(find.text('Reader'), findsOneWidget);
    expect(find.text('Go back'), findsWidgets);
    expect(find.text('Open library'), findsOneWidget); // host is desktop
  });
}
