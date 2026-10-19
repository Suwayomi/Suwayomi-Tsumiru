// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// P2: on native desktop the AppBar (which held the Server / On device
// TabBar) is removed, so the tab selector must render at the top of the
// desktop body instead, like Browse's tabs.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/manga_book/domain/downloads/downloads_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/downloads/controller/downloads_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/downloads/downloads_screen.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_settings_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../../../../../helpers/legacy_account_access.dart';

class _EmptyDownloads extends DownloadsMap {
  @override
  Map<int, DownloadDto> build() => const {};
}

Future<void> _pump(WidgetTester tester) async {
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
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null),
  );
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        settledAccountAccessProvider.overrideWithValue(legacyAccountAccess),
        downloadsMapProvider.overrideWith(_EmptyDownloads.new),
        downloadStatusProvider.overrideWith((ref) async => null),
        downloadUpdatesProvider.overrideWith(
          (ref) => const Stream<DownloadUpdatesDto?>.empty(),
        ),
        offlineEnabledProvider.overrideWithValue(false),
        offlineHasPendingProvider.overrideWith(
          (ref) => Stream.value(false),
        ),
        offlineDownloadsPausedProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DownloadsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desktop body keeps both tabs and switches to On device', (
    tester,
  ) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);

    expect(find.text('Server'), findsOneWidget);
    expect(find.text('On device'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);

    // The tabs sit above the tab bodies, like Browse's tabs.
    final tabBarRect = tester.getRect(find.byType(TabBar));
    final viewRect = tester.getRect(find.byType(TabBarView));
    expect(tabBarRect.bottom, lessThanOrEqualTo(viewRect.top + 1));

    await tester.tap(find.text('On device'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(DownloadsScreen)),
    )!;
    expect(find.text(l10n.offlineNotAvailable), findsOneWidget);
  });
}
