// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';

Future<Toast> _pumpToastHost(WidgetTester tester) async {
  late BuildContext hostContext;
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(builder: (context) {
      hostContext = context;
      return const SizedBox.shrink();
    }),
  ));
  return Toast(hostContext);
}

void main() {
  testWidgets('an error with nothing left to say still tells the user',
      (tester) async {
    final toast = await _pumpToastHost(tester);

    toast.showError('   ');
    await tester.pump();

    expect(find.text('Something went wrong!'), findsOneWidget);

    toast.close();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a real error message is shown as it is', (tester) async {
    final toast = await _pumpToastHost(tester);

    toast.showError("Extension can't be updated to the same version");
    await tester.pump();

    expect(find.text("Extension can't be updated to the same version"),
        findsOneWidget);

    toast.close();
    await tester.pump(const Duration(seconds: 5));
  });
}
