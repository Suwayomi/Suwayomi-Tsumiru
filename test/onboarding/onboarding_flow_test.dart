// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

const _aboutOk =
    '{"data":{"aboutServer":{"name":"Suwayomi-Server","version":"2.3.2162"}}}';
const _downloadOk = '{"data":{"downloadStatus":{"state":"STOPPED"}}}';

http.Client _openServerClient() => MockClient.streaming((request, body) async {
  final q =
      ((jsonDecode(await body.bytesToString()) as Map)['query'] as String);
  return http.StreamedResponse(
    Stream.value(
      utf8.encode(q.contains('aboutServer') ? _aboutOk : _downloadOk),
    ),
    200,
  );
});

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
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
      expect(find.byType(Image), findsNWidgets(1));

      await _tap(tester, find.text('Next'));
      expect(find.text('Connect your server'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);

      await _tap(tester, find.text('Next'));
      expect(find.text("You're all set"), findsNothing);
      expect(
        find.text("Enter your server's address, or tap Search my network."),
        findsOneWidget,
      );
      expect(find.text('Connect your server'), findsOneWidget);

      await _tap(tester, find.text('Back'));
      expect(find.text('Welcome to Tsumiru'), findsOneWidget);
    },
  );

  testWidgets('unparseable server address fails fast and a retest works', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          onboardingHttpClientProvider.overrideWithValue(_openServerClient),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tap(tester, find.text('Next'));
    expect(find.text('Connect your server'), findsOneWidget);

    final urlField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Server URL',
    );
    expect(urlField, findsOneWidget);
    await tester.scrollUntilVisible(
      urlField,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      urlField,
      'http://127.0.0.1:8092http://192.168.2.5:4569',
    );
    await tester.pumpAndSettle();

    await _tap(tester, find.text('Test connection'));

    expect(find.text('Invalid Server URL'), findsOneWidget);
    expect(find.text('Checking connection…'), findsNothing);
    expect(
      find.text(
        "If it's behind a reverse proxy, try its https address instead.",
      ),
      findsNothing,
    );

    await tester.enterText(urlField, '');
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Test connection'));
    expect(
      find.text("Enter your server's address, or tap Search my network."),
      findsOneWidget,
    );
    expect(find.text('Invalid Server URL'), findsNothing);

    await tester.enterText(
      urlField,
      'http://127.0.0.1:8092http://192.168.2.5:4569',
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Next'));
    expect(find.text('Invalid Server URL'), findsOneWidget);
    expect(sp.getBool('onboarding.advanceAfterProbe'), isNot(true));

    await tester.enterText(urlField, 'http://192.168.2.4:4568');
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Test connection'));
    expect(find.textContaining('Connected'), findsOneWidget);
    expect(find.text('Connect your server'), findsOneWidget);
    expect(find.text("You're all set"), findsNothing);
  });
}
