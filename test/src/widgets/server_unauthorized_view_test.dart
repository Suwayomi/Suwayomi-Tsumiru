// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/platform/web_auth_mode.dart';
import 'package:tsumiru/src/widgets/server_unauthorized_view.dart';

const _unsupportedMessage =
    "This server uses a sign-in method the browser version can't use. Set the server's authentication mode to UI login, or use the Android, iOS or desktop app.";

Future<void> _pump(
  WidgetTester tester, {
  bool isWeb = false,
  AuthType? savedAuthType,
}) async {
  SharedPreferences.setMockInitialValues({
    if (savedAuthType != null) 'authType': savedAuthType.index,
  });
  final container = ProviderContainer(
    overrides: [
      isWebProvider.overrideWithValue(isWeb),
      sharedPreferencesProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: ServerUnauthorizedView(message: 'Unauthorized'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Unmounts the tree and flushes Riverpod's zero-length auto-dispose timer,
/// which otherwise trips the pending-timer invariant at test end.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('passes the server message through off web', (tester) async {
    await _pump(tester, savedAuthType: AuthType.basic);

    expect(find.text('Unauthorized'), findsOneWidget);
    expect(find.text(_unsupportedMessage), findsNothing);
    await _unmount(tester);
  });

  testWidgets('web with a saved basic login explains the mode instead', (
    tester,
  ) async {
    await _pump(tester, isWeb: true, savedAuthType: AuthType.basic);

    expect(find.text(_unsupportedMessage), findsOneWidget);
    expect(find.text('Unauthorized'), findsNothing);
    expect(find.text('Connection settings'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('web with a saved simple login explains the mode instead', (
    tester,
  ) async {
    await _pump(tester, isWeb: true, savedAuthType: AuthType.simpleLogin);

    expect(find.text(_unsupportedMessage), findsOneWidget);
    expect(find.text('Unauthorized'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('web with UI login keeps the server message', (tester) async {
    await _pump(tester, isWeb: true, savedAuthType: AuthType.uiLogin);

    expect(find.text('Unauthorized'), findsOneWidget);
    expect(find.text(_unsupportedMessage), findsNothing);
    await _unmount(tester);
  });
}
