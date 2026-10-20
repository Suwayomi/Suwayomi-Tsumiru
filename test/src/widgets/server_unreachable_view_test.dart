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
import 'package:tsumiru/src/widgets/server_unreachable_view.dart';

const _unsupportedMessage =
    "This server uses a sign-in method the browser version can't use. Set the server's authentication mode to UI login, or use the Android, iOS or desktop app.";
const _unconfirmedMessage =
    "This server didn't accept the browser's request. If it uses Basic auth or Simple login, set its authentication mode to UI login, or use the Android, iOS or desktop app. Otherwise check the address.";

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  VoidCallback? onRetry,
  bool hasCatalog = false,
  bool offlineEscape = true,
  bool isWeb = false,
  bool webNotFoundVerdict = false,
  AuthType? savedAuthType,
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
          body: ServerUnreachableView(
            onRetry: onRetry,
            offlineEscape: offlineEscape,
            webNotFoundVerdict: webNotFoundVerdict,
          ),
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
  testWidgets('shows the unreachable message and retries when offered', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text("Can't reach your server"), findsOneWidget);
    expect(find.text('Connection settings'), findsOneWidget);
    // No retry button without a retry callback.
    expect(find.text('Refresh'), findsNothing);
    await _unmount(tester);

    // With one, the retry button shows and fires.
    var retried = 0;
    await _pump(tester, onRetry: () => retried++);
    expect(find.text('Refresh'), findsOneWidget);
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(retried, 1);
    await _unmount(tester);
  });

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
    },
  );

  testWidgets('web guidance explains unsupported sign-in modes', (
    tester,
  ) async {
    // Basic and Simple login on web explain the mode.
    for (final auth in [AuthType.basic, AuthType.simpleLogin]) {
      await _pump(tester, isWeb: true, savedAuthType: auth);
      expect(find.text(_unsupportedMessage), findsOneWidget, reason: '$auth');
      expect(find.text('Connection settings'), findsOneWidget, reason: '$auth');
      await _unmount(tester);
    }

    // UI login on web keeps the unreachable message.
    await _pump(tester, isWeb: true, savedAuthType: AuthType.uiLogin);
    expect(find.text(_unsupportedMessage), findsNothing);
    expect(find.text("Can't reach your server"), findsOneWidget);
    await _unmount(tester);

    // Native keeps it too, whatever the saved mode.
    await _pump(tester, isWeb: false, savedAuthType: AuthType.basic);
    expect(find.text(_unsupportedMessage), findsNothing);
    expect(find.text("Can't reach your server"), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a 404 verdict gets the unconfirmed guidance only on web', (
    tester,
  ) async {
    await _pump(
      tester,
      isWeb: true,
      webNotFoundVerdict: true,
      savedAuthType: AuthType.none,
    );
    expect(find.text(_unconfirmedMessage), findsOneWidget);
    expect(find.text(_unsupportedMessage), findsNothing);
    await _unmount(tester);

    await _pump(
      tester,
      isWeb: false,
      webNotFoundVerdict: true,
      savedAuthType: AuthType.basic,
    );
    expect(find.text(_unconfirmedMessage), findsNothing);
    expect(find.text("Can't reach your server"), findsOneWidget);
    await _unmount(tester);
  });
}
