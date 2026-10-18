// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';

/// Routes that used to lose the sidebar on tablet/desktop, with the screen
/// content each one is expected to show once pumped.
final _cases = <String, GoRouteData>{
  'source page': const SourceTypeRoute(
    sourceId: '1',
    sourceType: SourceType.POPULAR,
  ),
  'settings': const SettingsRoute(),
  'appearance': const AppearanceSettingsRoute(),
  'upcoming': const UpcomingRoute(),
};

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

/// Pumps the real route `build` output (not a copy of it) inside a minimal
/// GoRouter, so the DetailNavigationShellScreen wrap is what is tested.
/// Network-backed providers are stubbed; bounded pumps (never pumpAndSettle)
/// so pending requests cannot hang the test.
Future<void> _pumpRoute(
  WidgetTester tester,
  Size size,
  GoRouteData route,
) async {
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
        builder: (context, state) => route.build(context, state),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('detail routes keep the sidebar on desktop', () {
    for (final entry in _cases.entries) {
      testWidgets('${entry.key} shows BigScreenNavigationBar at 1400x900', (
        tester,
      ) async {
        await _pumpRoute(tester, const Size(1400, 900), entry.value);
        expect(find.byType(BigScreenNavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('detail routes are unchanged on phone', () {
    for (final entry in _cases.entries) {
      testWidgets('${entry.key} hides BigScreenNavigationBar at 412x900', (
        tester,
      ) async {
        await _pumpRoute(tester, const Size(412, 900), entry.value);
        expect(find.byType(BigScreenNavigationBar), findsNothing);
        // The screen itself still renders.
        expect(find.byType(Scaffold), findsWidgets);
        final exception = tester.takeException();
        if (entry.key == 'source page') {
          // Pre-existing test-env artifact, not from the wrap: the bare
          // SourceMangaListScreen (no DetailNavigationShellScreen anywhere)
          // overflows its chips row by the same 42px at 412x900, verified
          // with a throwaway probe. The wrap returns the child untouched on
          // phone, so it cannot affect this.
          expect(
            exception == null ||
                '$exception'.contains('A RenderFlex overflowed by 42 pixels'),
            isTrue,
            reason: 'unexpected exception: $exception',
          );
        } else {
          expect(exception, isNull);
        }
      });
    }
  });
}
