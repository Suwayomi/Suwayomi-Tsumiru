// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Slice 4: searching "socks" returns the 6 SOCKS rows with their section
// breadcrumb, and opening the SOCKS host result lands on the Server page
// with that row highlighted.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/controller/server_controller.dart';
import 'package:tsumiru/src/features/settings/domain/settings/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/domain/settings/settings.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/graphql/__generated__/web_interface.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/web_interface_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/server_screen.dart';
import 'package:tsumiru/src/features/settings/search/settings_search_registry.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_en.dart';

/// Whether [element]'s row is mid-pulse: its highlight tint is up.
bool _elementHighlighted(Element element) {
  var found = false;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    final decoration = widget is DecoratedBox ? widget.decoration : null;
    if (decoration is BoxDecoration && (decoration.color?.a ?? 0) > 0) {
      found = true;
    }
    return true;
  });
  return found;
}

/// Id of the nearest [SettingsHighlightTarget] above [element].
String? _targetIdOf(Element element) {
  String? id;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is SettingsHighlightTarget) id ??= widget.id;
    return true;
  });
  return id;
}

SettingsDto _serverSettings() => Fragment$SettingsDto(
  backupInterval: 0,
  backupPath: '',
  backupTTL: 0,
  backupTime: '',
  ip: '0.0.0.0',
  port: 4567,
  socksProxyEnabled: true,
  socksProxyHost: 'localhost',
  socksProxyPassword: '',
  socksProxyPort: '1080',
  socksProxyUsername: '',
  socksProxyVersion: 5,
  flareSolverrEnabled: true,
  flareSolverrSessionName: 'default',
  flareSolverrSessionTtl: 15,
  flareSolverrTimeout: 60,
  flareSolverrUrl: 'http://localhost:8191',
  debugLogsEnabled: false,
  systemTrayEnabled: false,
  extensionRepos: const [],
  maxSourcesInParallel: 0,
  localSourcePath: '',
  globalUpdateInterval: 12,
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
  Future<SettingsDto?> build() async => _serverSettings();
}

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      settingsProvider.overrideWith(_FixedSettings.new),
      settledAccountAccessProvider.overrideWithValue(
        AccountAccess(capability: AccountCapability.unsupported),
      ),
      webInterfaceSettingsProvider.overrideWith(
        (ref) async => Fragment$WebInterfaceSettingsDto(
          webUIFlavor: Enum$WebUIFlavor.WEBUI,
          webUIChannel: Enum$WebUIChannel.STABLE,
          webUIUpdateCheckInterval: 12,
        ),
      ),
      webInterfaceFlavorsProvider.overrideWith(
        (ref) async => const [Enum$WebUIFlavor.WEBUI, Enum$WebUIFlavor.VUI],
      ),
      installedWebInterfaceProvider.overrideWith((ref) async => null),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  final l = AppLocalizationsEn();

  group('server settings search', () {
    test('socks finds the 6 SOCKS rows with the section breadcrumb', () {
      expect(serverSettingsSearchEntries, hasLength(19));
      final hits = matchSettingsEntries(
        entries: allSettingsSearchEntries,
        l: l,
        query: 'socks',
        isVisible: (_) => true,
      );
      expect(hits.map((e) => e.id).toList(), [
        'enableSocksProxy',
        'socksVersion',
        'socksHost',
        'socksPort',
        'socksUserName',
        'socksPassword',
      ]);
      for (final hit in hits) {
        expect(hit.breadcrumb(l), '${l.server} › ${l.socksProxy}');
      }
    });

    testWidgets('opening the SOCKS host entry highlights its row', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final container = await _container();
      final entry = serverSettingsSearchEntries.singleWhere(
        (e) => e.id == 'socksHost',
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => entry.open(context),
                child: const Text('open'),
              ),
            ),
          ),
          // Mirrors ServerSettingsRoute.build: the `highlight` query value
          // drives the scope.
          GoRoute(
            path: '/more/settings/server',
            builder: (_, _) => const ServerScreen(),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      // Settle the push without exhausting the ~3 s pulse: pumpAndSettle
      // would run the highlight to completion before the loop below looks.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(router.state.uri.queryParameters['highlight'], entry.id);

      Element? lit;
      for (var i = 0; i < 60 && lit == null; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final matches = find
            .text(l.socksHost)
            .evaluate()
            .where(_elementHighlighted)
            .toList();
        if (matches.length == 1) lit = matches.single;
      }
      if (lit == null) fail('socks host row never lit up');
      expect(_targetIdOf(lit), 'socksHost');
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });
}
