// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/app_theme.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/about/presentation/about/about_screen.dart';
import 'package:tsumiru/src/features/about/presentation/about/controllers/about_controller.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/features/settings/presentation/more/more_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/theme/app_theme_builder.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';
import 'package:tsumiru/src/widgets/tsumiru_logo.dart';

const _seed = Color(0xFF7C7BFF);
const _darkIcon = 'assets/icons/dark_icon.png';
const _onLight = 'assets/icons/logo_on_light.png';
const _shadow = 'assets/icons/logo_shadow.png';
const _foreground = 'assets/icons/logo_foreground.png';

bool _isAsset(Widget widget, String path) =>
    widget is Image &&
    widget.image is AssetImage &&
    (widget.image as AssetImage).assetName == path;

Finder _image(String path) => find.byWidgetPredicate((w) => _isAsset(w, path));

Future<SharedPreferences> _prefs({AppTheme theme = AppTheme.royal}) async {
  SharedPreferences.setMockInitialValues({DBKeys.appTheme.name: theme.index});
  return SharedPreferences.getInstance();
}

ThemeData _theme(AppTheme theme, Brightness brightness) => buildAppTheme(
  theme: theme,
  brightness: brightness,
  customSeed: _seed,
  amoled: false,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required AppTheme theme,
  required Brightness brightness,
}) async {
  final prefs = await _prefs(theme: theme);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: _theme(theme, brightness),
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('Indigo Night dark draws the original artwork', (tester) async {
    await _pump(
      tester,
      const TsumiruLogo(size: 48),
      theme: AppTheme.indigoNight,
      brightness: Brightness.dark,
    );

    expect(_image(_darkIcon), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    expect(_image(_shadow), findsNothing);
  });

  testWidgets('Royal dark tints the shadow and keeps the foreground', (
    tester,
  ) async {
    await _pump(
      tester,
      const TsumiruLogo(size: 48),
      theme: AppTheme.royal,
      brightness: Brightness.dark,
    );

    expect(find.byType(ShaderMask), findsOneWidget);
    expect(_image(_shadow), findsOneWidget);
    expect(_image(_foreground), findsOneWidget);
    expect(_image(_darkIcon), findsNothing);
  });

  testWidgets('light themes draw the light artwork', (tester) async {
    await _pump(
      tester,
      const TsumiruLogo(size: 48),
      theme: AppTheme.royal,
      brightness: Brightness.light,
    );

    expect(_image(_onLight), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('the sidebar header uses TsumiruLogo', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(await _prefs()),
          downloadsPausedBadgeProvider.overrideWith((ref) => false),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: _theme(AppTheme.royal, Brightness.dark),
          home: Scaffold(
            body: Row(
              children: [
                BigScreenNavigationBar(
                  selectedIndex: 0,
                  onDestinationSelected: (_) {},
                ),
                const Expanded(child: SizedBox.expand()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TsumiruLogo), findsOneWidget);
  });

  testWidgets('the About screen uses TsumiruLogo', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(await _prefs()),
          packageInfoProvider.overrideWithValue(
            PackageInfo(
              appName: 'Tsumiru',
              packageName: 'app.tsumiru',
              version: '1.4.0',
              buildNumber: '59',
            ),
          ),
          aboutProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: _theme(AppTheme.royal, Brightness.dark),
          home: const AboutScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TsumiruLogo), findsOneWidget);
  });

  testWidgets('the More screen uses TsumiruLogo', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(await _prefs()),
          failedUpdateCountProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: _theme(AppTheme.royal, Brightness.dark),
          home: const MoreScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TsumiruLogo), findsOneWidget);
  });
}
