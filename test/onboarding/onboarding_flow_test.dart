// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
      'wizard advances theme→server, gates Next until verified, Back returns',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Step 1: welcome + theme. The big brand logo sits above the heading
    // (header swirl + the large logo → two brand images on this step), and a
    // top-right Skip escape is offered.
    expect(find.text('Welcome to Tsumiru'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));

    // Advance to step 2 (theme step is always completable).
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Connect your server'), findsOneWidget);
    // Skip is still offered on the server step.
    expect(find.text('Skip'), findsOneWidget);

    // Next is gated until a connection verifies — tapping must NOT finish.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text("You're all set"), findsNothing);
    expect(find.text('Connect your server'), findsOneWidget);

    // Back returns to the theme step.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Tsumiru'), findsOneWidget);
  });
}
