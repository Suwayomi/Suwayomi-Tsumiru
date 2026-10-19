// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// P2: pushing the same location twice must not lose the remaining page's
// toolbar on pop. Location-keyed registrations let the newer page overwrite
// the older page's entry, so popping the newer page removes the only entry
// and the older page is left without its toolbar.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';

Finder _inBar(Finder finder) => find.descendant(
  of: find.byType(DesktopTopBar),
  matching: finder,
);

void main() {
  setUp(() => debugDesktopPlatformOverride = true);
  tearDown(() => debugDesktopPlatformOverride = null);

  testWidgets(
    'pushing one location twice keeps the older toolbar after one pop',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'), (
            call,
          ) async {
            if (call.method == 'isMaximized') return false;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding
            .instance
            .defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('window_manager'),
              null,
            ),
      );
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          ShellRoute(
            builder: (context, state, child) => Scaffold(
              body: Column(
                children: [
                  if (showsMergedTopBar(context)) const DesktopTopBar(),
                  Expanded(child: child),
                ],
              ),
            ),
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) =>
                    const Center(child: Text('Home page')),
              ),
              GoRoute(
                path: '/settings',
                builder: (context, state) => TopBarSlot(
                  minWidth: 200,
                  content: const SizedBox(
                    height: 40,
                    child: Center(child: Text('Settings toolbar')),
                  ),
                  child: const Center(child: Text('Settings page')),
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            downloadsPausedBadgeProvider.overrideWith((ref) => false),
            extensionUpdateBadgeCountProvider.overrideWith((ref) async => 0),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      router.push('/settings');
      await tester.pumpAndSettle();
      expect(_inBar(find.text('Settings toolbar')), findsOneWidget);

      // The same location on top of itself: both pages stay mounted with the
      // same key, and the bar still shows a toolbar.
      router.push('/settings');
      await tester.pumpAndSettle();
      expect(_inBar(find.text('Settings toolbar')), findsOneWidget);

      // Popping the newer page must leave the older page's toolbar behind.
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Settings page'), findsOneWidget);
      expect(_inBar(find.text('Settings toolbar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
