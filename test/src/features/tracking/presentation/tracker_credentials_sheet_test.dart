// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/tracking/presentation/login/tracker_credentials_sheet.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('credentials sheet has username and password fields',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TrackerCredentialsSheet(
          trackerName: 'MangaUpdates',
          onSubmit: (_, __) {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('credentials sheet calls onSubmit with entered values',
      (tester) async {
    String? capturedUsername;
    String? capturedPassword;

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TrackerCredentialsSheet(
          trackerName: 'MyAnimeList',
          onSubmit: (u, p) {
            capturedUsername = u;
            capturedPassword = p;
          },
        ),
      ),
    ));
    await tester.pump();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'testuser');
    await tester.enterText(fields.at(1), 'hunter2');

    final loginButton = find.widgetWithText(FilledButton, 'Log in');
    expect(loginButton, findsOneWidget);
    await tester.tap(loginButton);
    await tester.pump();

    expect(capturedUsername, 'testuser');
    expect(capturedPassword, 'hunter2');
  });
}
