// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/browse_center/data/extension_store_repository/extension_store_repository.dart';
import 'package:tsumiru/src/features/browse_center/domain/extension_store/extension_store_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/browse/browse_screen.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/extension_screen.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension_store/extension_store_screen.dart';
import 'package:tsumiru/src/features/settings/controller/server_controller.dart';
import 'package:tsumiru/src/features/settings/domain/settings/settings.dart';
import 'package:tsumiru/src/features/settings/presentation/browse/browse_settings_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/browse/data/browse_settings_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

// Gate rule under test: only a resolved `true` shows store management; older
// servers (resolved `false`) nudge to update, and a pending/errored probe
// hides it. Never completing == still pending.
final _neverResolves = Completer<bool>().future;
final _storeListNeverResolves =
    Completer<({List<ExtensionStore> stores, int totalCount})?>().future;

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

Widget _browseHarness(List<Override> overrides) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => BrowseScreen(
          currentIndex: 1,
          onDestinationSelected: (_) {},
          children: const [
            Center(child: Text('sources')),
            Center(child: Text('extensions')),
            Center(child: Text('migrate')),
          ],
        ),
      ),
      GoRoute(
        path: '/more/settings/browse/extension-store',
        builder: (context, state) => const ExtensionStoreScreen(),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

final _fakeSettings = SettingsDto(
  backupInterval: 0,
  backupPath: '',
  backupTTL: 0,
  backupTime: '',
  ip: '',
  port: 0,
  socksProxyEnabled: false,
  socksProxyHost: '',
  socksProxyPassword: '',
  socksProxyPort: '',
  socksProxyUsername: '',
  socksProxyVersion: 4,
  flareSolverrEnabled: false,
  flareSolverrSessionName: '',
  flareSolverrSessionTtl: 0,
  flareSolverrTimeout: 0,
  flareSolverrUrl: '',
  debugLogsEnabled: false,
  systemTrayEnabled: false,
  // ignore: deprecated_member_use_from_same_package
  extensionRepos: const [],
  maxSourcesInParallel: 1,
  localSourcePath: '',
  globalUpdateInterval: 0,
  updateMangas: false,
  excludeCompleted: false,
  excludeNotStarted: false,
  excludeUnreadChapters: false,
  downloadAsCbz: false,
  downloadsPath: '',
  autoDownloadNewChapters: false,
  autoDownloadNewChaptersLimit: 0,
  excludeEntryWithUnreadChapters: false,
);

class _FixedSettings extends Settings {
  @override
  Future<SettingsDto?> build() => Future.value(_fakeSettings);
}

Future<Widget> _settingsHarness(List<Override> overrides) async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      settingsProvider.overrideWith(_FixedSettings.new),
      browseSettingsRepositoryProvider
          .overrideWithValue(BrowseSettingsRepository(_dummyClient())),
      ...overrides,
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const BrowseSettingsScreen(),
    ),
  );
}

void main() {
  group('Extensions-tab app-bar affordance', () {
    testWidgets('store-capable: tooltip is Extension stores and pushes the store screen',
        (tester) async {
      await tester.pumpWidget(_browseHarness([
        extensionStoreSupportProvider.overrideWith((ref) async => true),
      ]));
      await tester.pump();

      expect(find.byTooltip('Extension stores'), findsOneWidget);
      expect(find.byTooltip('Extension Repository'), findsNothing);

      await tester.tap(find.byTooltip('Extension stores'));
      await tester.pumpAndSettle();

      expect(find.byType(ExtensionStoreScreen), findsOneWidget);
    });

    testWidgets('not store-capable: no extension affordance', (tester) async {
      await tester.pumpWidget(_browseHarness([
        extensionStoreSupportProvider.overrideWith((ref) async => false),
      ]));
      await tester.pump();

      expect(find.byTooltip('Extension stores'), findsNothing);
    });

    testWidgets('gate pending: no affordance, nothing flickers or crashes',
        (tester) async {
      await tester.pumpWidget(_browseHarness([
        extensionStoreSupportProvider.overrideWith((ref) => _neverResolves),
      ]));
      await tester.pump();

      expect(find.byTooltip('Extension stores'), findsNothing);
    });

    testWidgets('gate errors: no affordance, nothing flickers or crashes',
        (tester) async {
      await tester.pumpWidget(_browseHarness([
        extensionStoreSupportProvider
            .overrideWith((ref) async => throw Exception('probe failed')),
      ]));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Extension stores'), findsNothing);
    });
  });

  group('Browse settings row', () {
    testWidgets('store-capable: row title is Extension stores with the count subtitle',
        (tester) async {
      await tester.pumpWidget(await _settingsHarness([
        extensionStoreSupportProvider.overrideWith((ref) async => true),
        extensionStoreListProvider.overrideWith(
          (ref) async => (stores: <ExtensionStore>[], totalCount: 3),
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Extension stores'), findsOneWidget);
      expect(find.text('3 stores'), findsOneWidget);
      expect(find.text('Extension Repository'), findsNothing);
    });

    testWidgets('store-capable but count still loading: falls back to the store description',
        (tester) async {
      await tester.pumpWidget(await _settingsHarness([
        extensionStoreSupportProvider.overrideWith((ref) async => true),
        extensionStoreListProvider
            .overrideWith((ref) => _storeListNeverResolves),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Extension stores'), findsOneWidget);
      expect(
        find.text('Add extension stores your server installs from'),
        findsOneWidget,
      );
    });

    testWidgets('not store-capable: row nudges to update the server',
        (tester) async {
      await tester.pumpWidget(await _settingsHarness([
        extensionStoreSupportProvider.overrideWith((ref) async => false),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Extension stores'), findsOneWidget);
      expect(
        find.text('Update your Suwayomi server to manage extensions'),
        findsOneWidget,
      );
    });

    testWidgets('gate pending: nudge row, nothing flickers or crashes',
        (tester) async {
      await tester.pumpWidget(await _settingsHarness([
        extensionStoreSupportProvider.overrideWith((ref) => _neverResolves),
      ]));
      await tester.pumpAndSettle();

      expect(
        find.text('Update your Suwayomi server to manage extensions'),
        findsOneWidget,
      );
    });

    testWidgets('gate errors: nudge row, nothing flickers or crashes',
        (tester) async {
      await tester.pumpWidget(await _settingsHarness([
        extensionStoreSupportProvider
            .overrideWith((ref) async => throw Exception('probe failed')),
      ]));
      await tester.pumpAndSettle();

      expect(
        find.text('Update your Suwayomi server to manage extensions'),
        findsOneWidget,
      );
    });
  });

  group('Extensions tab body', () {
    Widget bodyHarness(List<Override> overrides) => ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: ExtensionScreen()),
          ),
        );

    testWidgets('not store-capable: shows the update-server nudge',
        (tester) async {
      await tester.pumpWidget(bodyHarness([
        extensionStoreSupportProvider.overrideWith((ref) async => false),
      ]));
      await tester.pumpAndSettle();

      expect(
        find.text('Update your Suwayomi server to manage extensions'),
        findsOneWidget,
      );
    });

    testWidgets('gate pending: shows a loader, not the nudge', (tester) async {
      await tester.pumpWidget(bodyHarness([
        extensionStoreSupportProvider.overrideWith((ref) => _neverResolves),
      ]));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.text('Update your Suwayomi server to manage extensions'),
        findsNothing,
      );
    });
  });
}
