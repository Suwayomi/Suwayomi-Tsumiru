// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Slice 1 drift guard: every registry entry for a page must exist as a
// SettingsHighlightTarget on that page, and every target on the page must
// have a registry entry. Screens are pumped with every condition satisfied
// (keyboard runtime is inherent to the test VM; auto-refresh defaults on;
// theme dark + custom; recommendations on; full permissions), so a new
// conditional tile without an entry — or an entry whose tile was removed —
// fails here, not silently in search.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/app_theme.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/account_repository.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/library/data/default_category.dart';
import 'package:tsumiru/src/features/library/domain/category/category_model.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/settings/controller/server_controller.dart';
import 'package:tsumiru/src/features/settings/data/user_settings.dart';
import 'package:tsumiru/src/features/settings/domain/settings/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/domain/settings/settings.dart';
import 'package:tsumiru/src/features/settings/presentation/appearance/appearance_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/appearance/widgets/app_theme_selector/app_theme_providers.dart';
import 'package:tsumiru/src/features/settings/presentation/general/general_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/library/data/library_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/library/library_settings_screen.dart';
import 'package:tsumiru/src/features/settings/search/settings_search_registry.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

class _FixedSettings extends Settings {
  @override
  Future<SettingsDto?> build() async => _serverSettings();
}

class _EmptyCategories extends CategoryController {
  @override
  Future<List<CategoryDto>?> build() async => [];
}

class _CustomTheme extends AppThemeKey {
  @override
  AppTheme? build() => AppTheme.custom;
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

Future<ProviderContainer> _container({
  List<dynamic> extra = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(sp), ...extra],
  );
  return container;
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ProviderContainer container,
  Widget screen,
) async {
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectIdsMatchRegistry(
  WidgetTester tester,
  List<SettingsSearchEntry> registered,
) {
  expect(tester.takeException(), isNull);
  // skipOffstage: false — trailing rows are built inside the cache extent
  // but sit below the fold; they still need registry entries.
  final onScreen = tester
      .widgetList<SettingsHighlightTarget>(
        find.byType(SettingsHighlightTarget, skipOffstage: false),
      )
      .map((w) => w.id)
      .toList();
  final ids = registered.map((e) => e.id).toList();
  expect(
    onScreen.toSet(),
    ids.toSet(),
    reason: 'every entry has a target and every target has an entry',
  );
  expect(onScreen, hasLength(ids.length), reason: 'no duplicate targets');
}

void main() {
  group('settings registry drift guard', () {
    testWidgets('General entries match GeneralScreen targets', (tester) async {
      await _pumpScreen(
        tester,
        await _container(),
        const GeneralScreen(),
      );
      _expectIdsMatchRegistry(tester, generalSettingsSearchEntries);
    });

    testWidgets('Appearance entries match AppearanceScreen targets', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        await _container(
          extra: [appThemeKeyProvider.overrideWith(_CustomTheme.new)],
        ),
        const AppearanceScreen(),
      );
      _expectIdsMatchRegistry(tester, appearanceSettingsSearchEntries);
    });

    testWidgets('Library entries match LibrarySettingsScreen targets', (
      tester,
    ) async {
      final dummyLink = HttpLink('http://localhost/');
      final dummyClient = GraphQLClient(
        link: dummyLink,
        cache: GraphQLCache(),
      );
      final container = await _container(
        extra: [
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
          settledDefaultCategoryIdProvider.overrideWithValue(0),
          librarySettingsRepositoryProvider.overrideWithValue(
            LibrarySettingsRepository(
              dummyClient,
              routing: UserSettingsRouting(
                account: AccountRepository(dummyClient),
                access: () => AccountAccess(
                  capability: AccountCapability.unsupported,
                ),
                settings: () async => _serverSettings(),
                updated: () {},
              ),
            ),
          ),
        ],
      );
      await _pumpScreen(tester, container, const LibrarySettingsScreen());
      _expectIdsMatchRegistry(tester, librarySettingsSearchEntries);
    });
  });
}
