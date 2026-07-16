// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/presentation/offline_server_mismatch_banner.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:hooks_riverpod/misc.dart';

/// Load the SDK's Roboto so captured screenshots have readable text (test hosts
/// otherwise render the Ahem box font). Best-effort — falls through on CI.
Future<void> _loadRoboto() async {
  const candidates = [
    '/var/home/valyth/development/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
  ];
  for (final p in candidates) {
    final f = File(p);
    if (f.existsSync()) {
      final loader = FontLoader('Roboto')
        ..addFont(f.readAsBytes().then((b) => ByteData.view(b.buffer)));
      await loader.load();
      return;
    }
  }
}

Future<void> _capture(WidgetTester tester, Key rootKey, String name) async {
  final dir = Directory('build/offline_banner_screenshots')
    ..createSync(recursive: true);
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Widget _app(List<Override> overrides, Key rootKey, {String appBarTitle = 'Library'}) =>
    ProviderScope(
      overrides: overrides,
      child: RepaintBoundary(
        key: rootKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            appBar: AppBar(title: Text(appBarTitle)),
            body: const Column(
              children: [
                OfflineServerMismatchBanner(showAfterDismissal: true),
                Expanded(child: Center(child: Text('library grid…'))),
              ],
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(_loadRoboto);

  testWidgets('active mismatch: banner shows message + Dismiss/Clear, and '
      'Dismiss persists the pair', (tester) async {
    tester.view.physicalSize = const Size(1080, 520);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    const mismatch = OfflineServerMismatch(
        catalogServer: 'server-A', currentServer: 'server-B', dismissed: false);
    final rootKey = GlobalKey();

    await tester.pumpWidget(_app([
      sharedPreferencesProvider.overrideWithValue(prefs),
      offlineServerMismatchProvider.overrideWith((ref) async => mismatch),
    ], rootKey));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(OfflineServerMismatchBanner)))!;
    expect(find.byType(MaterialBanner), findsOneWidget);
    expect(find.text(l10n.offlineServerMismatch), findsOneWidget);
    expect(find.widgetWithText(TextButton, l10n.offlineServerMismatchDismiss),
        findsOneWidget);
    expect(find.widgetWithText(TextButton, l10n.offlineServerMismatchClear),
        findsOneWidget);

    await _capture(tester, rootKey, 'banner_active');

    await tester.tap(
        find.widgetWithText(TextButton, l10n.offlineServerMismatchDismiss));
    await tester.pumpAndSettle();

    expect(
      prefs.getStringList(DBKeys.offlineServerMismatchDismissedList.name),
      contains('server-A\nserver-B'),
      reason: 'Dismiss persists the (catalog, current) pair',
    );
  });

  testWidgets('dismissed mismatch: banner still shows the disabled state with '
      'a clear-to-enable action', (tester) async {
    tester.view.physicalSize = const Size(1080, 520);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    const mismatch = OfflineServerMismatch(
        catalogServer: 'server-A', currentServer: 'server-B', dismissed: true);
    final rootKey = GlobalKey();

    await tester.pumpWidget(_app([
      sharedPreferencesProvider.overrideWithValue(prefs),
      offlineServerMismatchProvider.overrideWith((ref) async => mismatch),
    ], rootKey, appBarTitle: 'Connection'));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(OfflineServerMismatchBanner)))!;
    expect(find.text(l10n.offlineServerMismatchDisabled), findsOneWidget);
    expect(
        find.widgetWithText(
            TextButton, l10n.offlineServerMismatchClearAction),
        findsOneWidget);
    // No Dismiss once already dismissed.
    expect(find.widgetWithText(TextButton, l10n.offlineServerMismatchDismiss),
        findsNothing);

    await _capture(tester, rootKey, 'banner_dismissed');
  });
}
