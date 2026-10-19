// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// P1: pushing a route above the shells (the reader, on the navigator above
// the shell pages) must bring back the standalone 40 px title strip. The
// shell stays mounted offstage, so a bare mounted-bar count keeps suppressing
// the strip and the pushed route loses its drag area and window buttons.
// Popping must restore exactly one bar and no strip.

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
import 'package:tsumiru/src/widgets/desktop/desktop_title_bar.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_window_scaffold.dart';
import 'package:window_manager/window_manager.dart';

Finder _inStrip(Finder finder) => find.descendant(
  of: find.byType(DesktopTitleBar),
  matching: finder,
);

void main() {
  setUp(() => debugDesktopPlatformOverride = true);
  tearDown(() => debugDesktopPlatformOverride = null);

  testWidgets(
    'pushing above the shells restores the strip; pop restores one bar',
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
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          downloadsPausedBadgeProvider.overrideWith((ref) => false),
          extensionUpdateBadgeCountProvider.overrideWith((ref) async => 0),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/lib',
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
                path: '/lib',
                builder: (context, state) => TopBarSlot(
                  minWidth: 200,
                  content: const SizedBox(
                    height: 40,
                    child: Center(child: Text('Library toolbar')),
                  ),
                  child: const Center(child: Text('Library page')),
                ),
              ),
            ],
          ),
          // Above the shell: the shell page stays mounted offstage, like the
          // reader pushed on the quick-open navigator above the shells.
          GoRoute(
            path: '/reader',
            builder: (context, state) =>
                const Center(child: Text('Reader page')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) =>
                DesktopWindowScaffold(child: child!),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Library page'), findsOneWidget);
      expect(container.read(mergedTopBarRegistryProvider), 1);
      expect(find.byType(DesktopTopBar), findsOneWidget);
      expect(find.byType(DesktopTitleBar), findsNothing);

      router.push('/reader');
      await tester.pumpAndSettle();

      expect(find.text('Reader page'), findsOneWidget);
      expect(container.read(mergedTopBarRegistryProvider), 0);
      expect(find.byType(DesktopTitleBar), findsOneWidget);
      expect(_inStrip(find.byType(DragToMoveArea)), findsOneWidget);
      expect(_inStrip(find.byType(WindowCaptionButton)), findsNWidgets(3));

      router.pop();
      await tester.pumpAndSettle();

      expect(find.text('Library page'), findsOneWidget);
      expect(container.read(mergedTopBarRegistryProvider), 1);
      expect(find.byType(DesktopTopBar), findsOneWidget);
      expect(find.byType(DesktopTitleBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
