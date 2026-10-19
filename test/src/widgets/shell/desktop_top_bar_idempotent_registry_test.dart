// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// P2: bar registration must be idempotent per mounted bar. Dependency changes
// (theme, MediaQuery) re-run didChangeDependencies after the scheduled
// show completed; scheduling another show each time grows the registry count,
// which a single dispose-time hide never balances, hiding the strip for good.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  setUp(() => debugDesktopPlatformOverride = true);
  tearDown(() => debugDesktopPlatformOverride = null);

  testWidgets(
    'dependency changes do not stack registrations; unmount returns to 0',
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

      var showBar = true;
      var brightness = Brightness.light;
      late void Function(void Function()) setOuter;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: ThemeData(brightness: brightness),
                localizationsDelegates:
                    AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: DesktopWindowScaffold(
                  child: Scaffold(
                    body: Column(
                      children: [
                        if (showBar) const DesktopTopBar(),
                        const Expanded(child: Center(child: Text('page'))),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(mergedTopBarRegistryProvider), 1);

      // Extra dependency changes on the same mounted bar: theme twice and a
      // MediaQuery resize. None may register the bar again.
      setOuter(() => brightness = Brightness.dark);
      await tester.pumpAndSettle();
      expect(container.read(mergedTopBarRegistryProvider), 1);

      setOuter(() => brightness = Brightness.light);
      await tester.pumpAndSettle();
      expect(container.read(mergedTopBarRegistryProvider), 1);

      tester.view.physicalSize = const Size(1300, 900);
      await tester.pumpAndSettle();
      expect(container.read(mergedTopBarRegistryProvider), 1);

      // Unmounting the one bar returns the count to 0 and the strip comes
      // back with its window controls.
      setOuter(() => showBar = false);
      await tester.pumpAndSettle();
      expect(container.read(mergedTopBarRegistryProvider), 0);
      expect(find.byType(DesktopTitleBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DesktopTitleBar),
          matching: find.byType(WindowCaptionButton),
        ),
        findsNWidgets(3),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
