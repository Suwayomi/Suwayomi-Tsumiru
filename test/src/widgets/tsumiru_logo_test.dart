// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';
import 'package:tsumiru/src/widgets/tsumiru_logo.dart';

const _seed = Color(0xFF7C7BFF);
const _darkIcon = 'assets/icons/dark_icon.png';
const _onLight = 'assets/icons/logo_on_light.png';
const _onLightForeground = 'assets/icons/logo_on_light_foreground.png';
const _onLightShadow = 'assets/icons/logo_on_light_shadow.png';
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

Future<void> _pumpInFullWidthBox(
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
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 600,
              child: ListView(children: [child]),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final (name, theme, brightness) in const [
    ('Indigo Night', AppTheme.indigoNight, Brightness.dark),
    ('Royal', AppTheme.royal, Brightness.dark),
    ('Royal light', AppTheme.royal, Brightness.light),
    ('Catppuccin light', AppTheme.catppuccin, Brightness.light),
  ]) {
    testWidgets('$name logo is centred in a full-width box', (tester) async {
      await _pumpInFullWidthBox(
        tester,
        const TsumiruLogo(size: 48),
        theme: theme,
        brightness: brightness,
      );

      final box = tester.getRect(find.byType(ListView));
      final images = find.byType(Image);
      expect(images, findsWidgets);
      for (var i = 0; i < images.evaluate().length; i++) {
        expect(
          tester.getCenter(images.at(i)).dx,
          moreOrLessEquals(box.center.dx),
        );
      }
    });

    testWidgets('$name logo is size x size under loose constraints', (
      tester,
    ) async {
      await _pump(
        tester,
        const TsumiruLogo(size: 48),
        theme: theme,
        brightness: brightness,
      );

      expect(tester.getSize(find.byType(TsumiruLogo)), const Size(48, 48));
    });
  }

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

  testWidgets('Indigo Night light draws the original artwork', (tester) async {
    await _pump(
      tester,
      const TsumiruLogo(size: 48),
      theme: AppTheme.indigoNight,
      brightness: Brightness.light,
    );

    expect(_image(_onLight), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    expect(_image(_onLightShadow), findsNothing);
    expect(_image(_onLightForeground), findsNothing);
  });

  testWidgets('Catppuccin light tints the shadow with its dark accent pair', (
    tester,
  ) async {
    await _pump(
      tester,
      const TsumiruLogo(size: 48),
      theme: AppTheme.catppuccin,
      brightness: Brightness.light,
    );

    expect(
      find.byWidgetPredicate(
        (w) => w is ShaderMask && w.blendMode == BlendMode.modulate,
      ),
      findsOneWidget,
    );
    expect(_image(_onLightShadow), findsOneWidget);
    expect(_image(_onLightForeground), findsOneWidget);
    expect(_image(_onLight), findsNothing);

    final dark = schemeFor(AppTheme.catppuccin, Brightness.dark, _seed);
    final expected = [dark.primary, dark.secondary]
      ..sort((a, b) => b.computeLuminance().compareTo(a.computeLuminance()));
    expect(logoShadowGradient(dark).colors, expected);
    expect(expected.first, isNot(expected.last));
  });

  testWidgets('the top bar brand block uses TsumiruLogo', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          if (call.method == 'isMaximized') return false;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'), null),
    );

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
            body: Column(
              children: [
                const DesktopTopBar(),
                Expanded(
                  child: Row(
                    children: [
                      BigScreenNavigationBar(
                        selectedIndex: 0,
                        onDestinationSelected: (_) {},
                      ),
                      const Expanded(child: SizedBox.expand()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The sidebar lost its header to the merged bar: the logo lives in the
    // brand block, exactly once.
    expect(find.byType(TsumiruLogo), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DesktopTopBar),
        matching: find.byType(TsumiruLogo),
      ),
      findsOneWidget,
    );
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
    // Externally-owned container: at the default 800x600 surface More mounts
    // the desktop search box, whose deferred focus-node unregister must flush
    // while the container is still alive (see account_screen_test).
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(await _prefs()),
        failedUpdateCountProvider.overrideWith((ref) async => 0),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
