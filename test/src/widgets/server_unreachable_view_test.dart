// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/server_unreachable_view.dart';

Future<void> _pump(WidgetTester tester, {VoidCallback? onRetry}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ServerUnreachableView(onRetry: onRetry)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the unreachable message and a Connection settings action',
      (tester) async {
    await _pump(tester);

    expect(find.text("Can't reach your server"), findsOneWidget);
    expect(find.text('Connection settings'), findsOneWidget);
  });

  testWidgets('retry button is shown only when a retry is provided',
      (tester) async {
    await _pump(tester);
    expect(find.text('Refresh'), findsNothing);

    var retried = 0;
    await _pump(tester, onRetry: () => retried++);
    expect(find.text('Refresh'), findsOneWidget);

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(retried, 1);
  });
}
