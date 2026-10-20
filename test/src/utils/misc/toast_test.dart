// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';

Future<Toast> _pumpToastHost(WidgetTester tester) async {
  late BuildContext hostContext;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return Toast(hostContext);
}

void main() {
  testWidgets('permission denial explains the account restriction', (
    tester,
  ) async {
    final toast = await _pumpToastHost(tester);
    toast.showError(
      'Exception while fetching data (/download) : Forbidden\r\n'
      'server.ForbiddenException: Forbidden',
    );
    await tester.pump();
    expect(
      find.text('Your account does not have permission for this action.'),
      findsOneWidget,
    );
    expect(find.textContaining('ForbiddenException'), findsNothing);
    toast.close();
    await tester.pump(const Duration(seconds: 5));
  });
}
