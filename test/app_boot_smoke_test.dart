// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/sorayomi.dart';

/// Pumps the real root widget and asserts it builds without throwing — a
/// root-build crash (e.g. `context.l10n` read above the `MaterialApp` that
/// installs localizations) passes every unit test but only surfaces here.
void main() {
  const notifChannel = MethodChannel('dexterous.com/flutter/local_notifications');

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // main.dart normally gets this instance from the native plugin registrant.
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, (call) async {
      if (call.method == 'getNotificationAppLaunchDetails') {
        return <String, Object?>{'notificationLaunchedApp': false};
      }
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, null);
  });

  testWidgets('app root builds and launches without throwing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // Keeps the test on the root scaffold's own build, not a real screen that
    // would need a live server.
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink())],
    );

    // The real client is Hive-backed and set up in main.dart before runApp.
    final client = GraphQLClient(
      link: HttpLink('http://localhost'),
      cache: GraphQLCache(),
    );

    // Android so the notification-gated startup code (skipped on web) runs
    // too; reset before flutter_test's end-of-test invariant check either way.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            routerConfigProvider.overrideWith((ref) => router),
            graphQlClientHolderProvider.overrideWithValue(ValueNotifier(client)),
          ],
          child: const Sorayomi(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
