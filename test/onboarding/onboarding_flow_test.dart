// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';

void main() {
  testWidgets('wizard retains the server step across root replacement', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    Widget app() => ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const OnboardingScreen(),
      ),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Connect your server'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text("You're all set"), findsNothing);
  });

  testWidgets('stored UI credentials do not skip the saved server step', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'auth.ui.accessToken': 'access',
      'auth.ui.refreshToken': 'refresh',
      'auth.ui.accountBinding': const AccountBinding(
        address: 'http://server',
        userId: 2,
        username: 'alice',
        catalogId: 'alice-root',
      ).encode(accessToken: 'access', refreshToken: 'refresh'),
    });
    SharedPreferences.setMockInitialValues({
      DBKeys.authType.name: AuthType.uiLogin.index,
      'onboarding.step': 1,
    });
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("You're all set"), findsNothing);
    expect(find.text('Connect your server'), findsOneWidget);
  });

  testWidgets(
    'wizard advances theme→server, validates an empty URL, Back returns',
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

      expect(find.text('Welcome to Tsumiru'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Connect your server'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text("You're all set"), findsNothing);
      expect(
        find.text("Enter your server's address, or tap Search my network."),
        findsOneWidget,
      );
      expect(find.text('Connect your server'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Tsumiru'), findsOneWidget);
    },
  );

  testWidgets('reduced motion swaps the onboarding step at once', (
    tester,
  ) async {
    await _pumpOnboarding(tester, reduceMotion: true);

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Welcome to Tsumiru'), findsNothing);
    expect(find.text('Connect your server'), findsOneWidget);
  });

  testWidgets(
    'without reduced motion the outgoing step is still on screen after one frame',
    (tester) async {
      await _pumpOnboarding(tester, reduceMotion: false);

      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Welcome to Tsumiru'), findsOneWidget);
      expect(find.text('Connect your server'), findsOneWidget);
    },
  );
}

class _ReduceMotionOn extends AppReduceMotion {
  @override
  bool build() => true;
}

Future<void> _pumpOnboarding(
  WidgetTester tester, {
  required bool reduceMotion,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        if (reduceMotion)
          appReduceMotionProvider.overrideWith(_ReduceMotionOn.new),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ReduceMotionScope(child: child!),
        home: const OnboardingScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
