// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Opening DownloadsSettingsRoute with tab=1 through its real buildPage (the
// path GoRouter takes) lands on the On device tab, and a highlight id in the
// same location still pulses its row. Guards the build/buildPage child from
// drifting again: buildPage must carry the same initialTab as build.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/library/domain/category/category_model.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/settings/controller/server_controller.dart';
import 'package:tsumiru/src/features/settings/data/user_settings.dart';
import 'package:tsumiru/src/features/settings/domain/settings/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/domain/settings/settings.dart';
import 'package:tsumiru/src/features/settings/search/settings_highlight_target.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_en.dart';
import 'package:tsumiru/src/routes/router_config.dart';

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
  ip: '',
  port: 0,
  socksProxyEnabled: false,
  socksProxyHost: '',
  socksProxyPassword: '',
  socksProxyPort: '',
  socksProxyUsername: '',
  socksProxyVersion: 0,
  flareSolverrEnabled: false,
  flareSolverrSessionName: '',
  flareSolverrSessionTtl: 0,
  flareSolverrTimeout: 0,
  flareSolverrUrl: '',
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

class _EmptyCategories extends CategoryController {
  @override
  Future<List<CategoryDto>?> build() async => [];
}

void main() {
  final l = AppLocalizationsEn();

  testWidgets(
    'DownloadsSettingsRoute buildPage with tab 1 selects On device '
    'and highlights the row',
    (tester) async {
      // Phone width: the shell wrapper returns the child unchanged, so the
      // page under test is exactly what buildPage built.
      tester.view.physicalSize = const Size(412, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          settingsProvider.overrideWith(_FixedSettings.new),
          personalSettingsProvider.overrideWith(
            (ref) async => _serverSettings(),
          ),
          personalSettingsStateProvider.overrideWithValue(
            PersonalSettingsState.ready,
          ),
          settledAccountAccessProvider.overrideWithValue(
            AccountAccess(capability: AccountCapability.unsupported),
          ),
          categoryControllerProvider.overrideWith(_EmptyCategories.new),
          offlineEnabledProvider.overrideWithValue(true),
          offlineUsageBytesProvider.overrideWith((ref) async => 0),
        ],
      );
      addTearDown(container.dispose);
      const route = DownloadsSettingsRoute(
        highlight: 'deviceDeleteWithBookmark',
        tab: 1,
      );
      // Same location GoRouter navigates to for this route object.
      expect(route.location, contains('tab=1'));
      expect(route.location, contains('highlight=deviceDeleteWithBookmark'));
      final router = GoRouter(
        initialLocation: route.location,
        routes: [
          // What GoRouter does with the typed route: decode the state into
          // the route object (same fields the generated _fromState reads),
          // then call its buildPage.
          GoRoute(
            path: '/more/settings/downloads',
            pageBuilder: (context, state) => DownloadsSettingsRoute(
              highlight: state.uri.queryParameters['highlight'],
              tab: int.tryParse(state.uri.queryParameters['tab'] ?? ''),
            ).buildPage(context, state),
          ),
        ],
      );
      addTearDown(router.dispose);
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Both parameters survived navigation, and the page honours the tab.
      expect(router.state.uri.queryParameters['highlight'], route.highlight);
      expect(router.state.uri.queryParameters['tab'], '1');
      final tabBar = tester.element(find.byType(TabBar));
      expect(DefaultTabController.of(tabBar).index, 1);

      // The On device delete row lights up — identified by target id, since
      // the Server tab holds a same-titled twin.
      Element? lit;
      for (var i = 0; i < 60 && lit == null; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final matches = find
            .text(l.allowDeletingBookmarkedChapters)
            .evaluate()
            .where(_elementHighlighted)
            .toList();
        if (matches.length == 1) lit = matches.single;
      }
      if (lit == null) fail('on-device row never lit up');
      expect(_targetIdOf(lit), 'deviceDeleteWithBookmark');
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    },
  );
}
