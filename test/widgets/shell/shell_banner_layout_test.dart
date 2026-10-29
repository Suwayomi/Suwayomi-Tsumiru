// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_window_scaffold.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';
import 'package:tsumiru/src/widgets/shell/detail_navigation_shell_screen.dart';

void main() {
  testWidgets('banner sits beside the rail and below the top bar', (
    tester,
  ) async {
    debugDesktopPlatformOverride = true;
    debugMacOSOverride = false;
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    final windowChannel = TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger;
    windowChannel.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'isMaximized' ? false : null,
    );
    addTearDown(() {
      debugDesktopPlatformOverride = null;
      debugMacOSOverride = null;
      tester.view.reset();
      windowChannel.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      );
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final messenger = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          downloadsPausedBadgeProvider.overrideWith((ref) => false),
          extensionUpdateBadgeCountProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp(
          scaffoldMessengerKey: messenger,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (_, child) => DesktopWindowScaffold(child: child!),
          home: const DetailNavigationShellScreen(
            child: Scaffold(body: Text('Page')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    messenger.currentState!.showMaterialBanner(
      MaterialBanner(
        content: const Text('Session expired'),
        actions: [TextButton(onPressed: () {}, child: const Text('Sign in'))],
      ),
    );
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byType(DesktopTopBar));
    final rail = tester.getRect(find.byType(BigScreenNavigationBar));
    final banner = tester.getRect(find.byType(MaterialBanner));
    expect(find.text('Session expired'), findsOneWidget);
    expect(bar.height, greaterThan(0));
    expect(rail.width, greaterThan(0));
    expect(banner.top, greaterThanOrEqualTo(bar.bottom));
    expect(banner.left, greaterThanOrEqualTo(rail.right));
    expect(banner.left, lessThan(1400));
  });
}
