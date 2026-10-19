// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source_manga_list/controller/source_manga_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/upcoming/controller/upcoming_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/features/settings/presentation/settings/settings_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';

class _ReduceMotionOn extends AppReduceMotion {
  @override
  bool build() => true;
}

final _source = SourceDto.fromJson({
  'displayName': 'Weeb Central (EN)',
  'iconUrl': '',
  'id': '1',
  'isConfigurable': false,
  'contentWarning': 'SAFE',
  'lang': 'en',
  'name': 'Weeb Central (EN)',
  'supportsLatest': true,
  '__typename': 'SourceType',
  'meta': [],
  'extension': {
    'pkgName': 'pkg',
    'repo': 'repo',
    'isObsolete': false,
    '__typename': 'ExtensionType',
  },
});

/// Minimal router around the real [SettingsRoute.buildPage], so the page (and
/// its transition) under test is the one the app uses. Bounded pumps only
/// (never pumpAndSettle) so pending requests cannot hang the test.
Future<GoRouter> _pumpPush(
  WidgetTester tester, {
  required Size size,
  bool reduceMotion = false,
  TargetPlatform? platform,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('home'))),
      ),
      GoRoute(
        path: '/more/settings',
        pageBuilder: (context, state) =>
            const SettingsRoute().buildPage(context, state),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (reduceMotion)
          appReduceMotionProvider.overrideWith(_ReduceMotionOn.new),
        sharedPreferencesProvider.overrideWithValue(preferences),
        downloadsPausedBadgeProvider.overrideWith((ref) => false),
        extensionUpdateBadgeCountProvider.overrideWith((ref) async => 0),
        sourceProvider('1').overrideWith((ref) async => _source),
        baseSourceMangaFilterListProvider(
          '1',
        ).overrideWith((ref) async => null),
        upcomingProvider.overrideWith((ref) async => UpcomingData.empty),
      ],
      child: MaterialApp.router(
        theme: platform == null ? null : ThemeData(platform: platform),
        routerConfig: router,
        builder: (context, child) => ReduceMotionScope(child: child!),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return router;
}

CustomTransitionPage _settingsPage(WidgetTester tester) {
  final route = ModalRoute.of(tester.element(find.byType(SettingsScreen)));
  return route!.settings as CustomTransitionPage;
}

void main() {
  testWidgets(
    'phone page uses the Android builder timing',
    (tester) async {
      final router = await _pumpPush(
        tester,
        size: const Size(412, 900),
        platform: TargetPlatform.android,
      );
      unawaited(router.push(const SettingsRoute().location));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final builder = const PredictiveBackPageTransitionsBuilder();
      final page = _settingsPage(tester);
      expect(page.transitionDuration, builder.transitionDuration);
      expect(page.reverseTransitionDuration, builder.reverseTransitionDuration);
      expect(page.transitionDuration, const Duration(milliseconds: 450));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone page uses the iOS builder timing',
    (tester) async {
      final router = await _pumpPush(
        tester,
        size: const Size(412, 900),
        platform: TargetPlatform.iOS,
      );
      unawaited(router.push(const SettingsRoute().location));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final builder = const CupertinoPageTransitionsBuilder();
      final page = _settingsPage(tester);
      expect(page.transitionDuration, builder.transitionDuration);
      expect(page.reverseTransitionDuration, builder.reverseTransitionDuration);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings fades without scaling the sidebar at 1400x900',
    (tester) async {
      final router = await _pumpPush(
        tester,
        size: const Size(1400, 900),
      );
      unawaited(router.push(const SettingsRoute().location));
      await tester.pump();
      // Half-way through the 150 ms transition.
      await tester.pump(const Duration(milliseconds: 75));

      final navBar = find.byType(BigScreenNavigationBar);
      expect(navBar, findsOneWidget);

      final fades = tester.widgetList<FadeTransition>(
        find.ancestor(of: navBar, matching: find.byType(FadeTransition)),
      );
      expect(fades, isNotEmpty);
      // Mid-transition: the fade is actually in flight, not instant.
      expect(
        fades.any((f) => f.opacity.value > 0.0 && f.opacity.value < 1.0),
        isTrue,
      );

      // No zoom: nothing between the sidebar and the route scales it.
      expect(
        find.ancestor(of: navBar, matching: find.byType(ScaleTransition)),
        findsNothing,
      );
      for (final transform in tester.widgetList<Transform>(
        find.ancestor(of: navBar, matching: find.byType(Transform)),
      )) {
        expect(transform.transform.getMaxScaleOnAxis(), 1.0);
      }

      // The sidebar never moves: same rect mid-transition and after.
      final during = tester.getRect(navBar);
      await tester.pump(const Duration(milliseconds: 75));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.getRect(navBar), during);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings keeps the platform transition at 412x900',
    (tester) async {
      final router = await _pumpPush(
        tester,
        size: const Size(412, 900),
        platform: TargetPlatform.android,
      );
      unawaited(router.push(const SettingsRoute().location));
      await tester.pump();
      // Half-way through the platform transition.
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byType(BigScreenNavigationBar), findsNothing);
      final route = ModalRoute.of(tester.element(find.byType(SettingsScreen)));
      expect(route, isA<PageRoute>());
      // Stable identity: a CustomTransitionPage even on phones, so resizing
      // across the 600 px breakpoint updates the route in place.
      final page = route!.settings;
      expect(page, isA<CustomTransitionPage>());
      final builder = const PredictiveBackPageTransitionsBuilder();
      expect(
        (page as CustomTransitionPage).transitionDuration,
        builder.transitionDuration,
      );
      expect(
        page.reverseTransitionDuration,
        builder.reverseTransitionDuration,
      );
      // The platform transition is actually in flight, not instant.
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings shows instantly with reduced motion at 1400x900',
    (tester) async {
      final router = await _pumpPush(
        tester,
        size: const Size(1400, 900),
        reduceMotion: true,
      );
      unawaited(router.push(const SettingsRoute().location));
      // The pushed route is built on the frame after insertion; with a
      // zero-length transition it is already settled then.
      await tester.pump();
      await tester.pump();

      final navBar = find.byType(BigScreenNavigationBar);
      expect(navBar, findsOneWidget);
      expect(
        find.ancestor(of: navBar, matching: find.byType(FadeTransition)),
        findsNothing,
      );
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
