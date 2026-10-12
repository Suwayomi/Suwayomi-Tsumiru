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
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';

class _ReduceMotionOn extends AppReduceMotion {
  @override
  bool build() => true;
}

Future<Toast> _pumpToastHost(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  late BuildContext hostContext;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (reduceMotion)
          appReduceMotionProvider.overrideWith(_ReduceMotionOn.new),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ReduceMotionScope(child: child!),
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
  testWidgets('under reduced motion two toasts each show and clear in turn', (
    tester,
  ) async {
    final toast = await _pumpToastHost(tester, reduceMotion: true);

    toast.show('first toast');
    toast.show('second toast');
    await tester.pump();
    expect(find.text('first toast'), findsOneWidget);
    expect(find.text('second toast'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('first toast'), findsNothing);
    expect(find.text('second toast'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('second toast'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('an error with nothing left to say still tells the user', (
    tester,
  ) async {
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

    expect(
      find.text("Extension can't be updated to the same version"),
      findsOneWidget,
    );

    toast.close();
    await tester.pump(const Duration(seconds: 5));
  });
}
