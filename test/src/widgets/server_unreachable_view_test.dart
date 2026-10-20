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
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/server_reachability.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/platform/web_auth_mode.dart';
import 'package:tsumiru/src/widgets/server_unauthorized_view.dart';
import 'package:tsumiru/src/widgets/server_unreachable_view.dart';

const _unsupportedMessage =
    "This server uses a sign-in method the browser version can't use. Set the server's authentication mode to UI login, or use the Android, iOS or desktop app.";

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool hasCatalog = false,
  bool offlineEscape = true,
  bool isWeb = false,
  AuthType? savedAuthType,
  bool unauthorized = false,
}) async {
  SharedPreferences.setMockInitialValues({
    if (savedAuthType != null) 'authType': savedAuthType.index,
  });
  final container = ProviderContainer(
    overrides: [
      offlineCatalogAvailableProvider.overrideWith((ref) async => hasCatalog),
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
        home: Scaffold(
          body: unauthorized
              ? const ServerUnauthorizedView(message: 'Unauthorized')
              : ServerUnreachableView(offlineEscape: offlineEscape),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Unmounts the tree to flush Riverpod's pending auto-dispose timer.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets(
    'View offline shows only with a catalog and a screen that uses it',
    (tester) async {
      // No catalog.
      await _pump(tester);
      expect(find.text('View offline'), findsNothing);
      await _unmount(tester);

      // Screens that ignore the pin.
      await _pump(tester, hasCatalog: true, offlineEscape: false);
      expect(find.text('View offline'), findsNothing);
      await _unmount(tester);

      // Catalog present: the action shows and sets the pin.
      final container = await _pump(tester, hasCatalog: true);
      expect(find.text('View offline'), findsOneWidget);
      await tester.tap(find.text('View offline'));
      await tester.pumpAndSettle();
      expect(container.read(viewOfflineNowProvider), isTrue);
      await _unmount(tester);

      // The 401 view follows the same sign-in rule: the server message passes
      // through off web, and unsupported modes get the web guidance.
      await _pump(tester, unauthorized: true, savedAuthType: AuthType.basic);
      expect(find.text('Unauthorized'), findsOneWidget);
      expect(find.text(_unsupportedMessage), findsNothing);
      await _unmount(tester);

      for (final auth in [AuthType.basic, AuthType.simpleLogin]) {
        await _pump(
          tester,
          unauthorized: true,
          isWeb: true,
          savedAuthType: auth,
        );
        expect(find.text(_unsupportedMessage), findsOneWidget, reason: '$auth');
        expect(find.text('Unauthorized'), findsNothing, reason: '$auth');
        await _unmount(tester);
      }

      // UI login on web keeps the server message.
      await _pump(
        tester,
        unauthorized: true,
        isWeb: true,
        savedAuthType: AuthType.uiLogin,
      );
      expect(find.text('Unauthorized'), findsOneWidget);
      expect(find.text(_unsupportedMessage), findsNothing);
      await _unmount(tester);
    },
  );
}
