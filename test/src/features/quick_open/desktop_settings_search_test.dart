// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Slice 1: the desktop unified dropdown gains a Settings section under Go to
// and above Search all sources; picking a row opens the setting's page with
// its highlight id, and Enter opens the first setting when settings are the
// only results.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/desktop_search_field.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_providers.dart';
import 'package:tsumiru/src/features/settings/controller/server_controller.dart';
import 'package:tsumiru/src/features/settings/domain/settings/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/domain/settings/settings.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/data/koreader_sync_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/domain/koreader_sync_domain.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/web_interface_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/data/syncyomi_settings_provider.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

const _desktop = Size(1400, 980);

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Fragment$MangaDto _manga(int id, String title) => Fragment$MangaDto(
  id: id,
  title: title,
  thumbnailUrl: null,
  bookmarkCount: 0,
  chapters: Fragment$MangaDto$chapters(totalCount: 4),
  downloadCount: 1,
  genre: const [],
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  unreadCount: 2,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/$id',
);

const _emptyCategories = AsyncData(<Fragment$CategoryDto>[]);

// Reachable server, so the server-gated rows (Library's Automatic Update,
// Browse, Downloads, Backup) render in search like they do on their pages.
SettingsDto _loadedSettings() => Fragment$SettingsDto(
  backupInterval: 0,
  backupPath: '',
  backupTTL: 0,
  backupTime: '',
  ip: '0.0.0.0',
  port: 4567,
  socksProxyEnabled: false,
  socksProxyHost: '',
  socksProxyPassword: '',
  socksProxyPort: '',
  socksProxyUsername: '',
  socksProxyVersion: 5,
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

class _LoadedSettings extends Settings {
  @override
  Future<SettingsDto?> build() async => _loadedSettings();
}

Future<ProviderContainer> _container({
  List<Fragment$MangaDto> library = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      libraryMangaListProvider.overrideWith((ref) async => library),
      visibleCategoryListProvider.overrideWithValue(_emptyCategories),
      // Same as unreachableServerStubs, but with a reachable server: the
      // server-gated search rows must render in these tests.
      settingsProvider.overrideWith(_LoadedSettings.new),
      webInterfaceSettingsProvider.overrideWith((ref) async => null),
      syncYomiSettingsProvider.overrideWith((ref) async => null),
      koreaderSyncSettingsProvider.overrideWith((ref) async => null),
      koSyncStatusProvider.overrideWith(
        (ref) async => const KoSyncStatus(isLoggedIn: false),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

GoRouter _router(ProviderContainer container) => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => Scaffold(
        body: Center(
          child: SizedBox(
            width: 500,
            child: Consumer(
              builder: (context, ref, _) => DesktopSearchField(
                query: ref.watch(unifiedSearchQueryProvider),
                onChanged: (value) =>
                    ref.read(unifiedSearchQueryProvider.notifier).state = value,
                onNavigate: () =>
                    ref.read(unifiedSearchQueryProvider.notifier).state = '',
              ),
            ),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/updates',
      builder: (_, _) =>
          const Scaffold(body: Center(child: Text('UPDATES PAGE'))),
    ),
    for (final page in ['general', 'appearance', 'library'])
      GoRoute(
        path: '/more/settings/$page',
        builder: (_, state) => Scaffold(
          body: Center(
            child: Text(
              'SETTINGS $page highlight=${state.uri.queryParameters['highlight']}',
            ),
          ),
        ),
      ),
    GoRoute(
      path: '/global-search',
      builder: (_, _) =>
          const Scaffold(body: Center(child: Text('GLOBAL SEARCH PAGE'))),
    ),
  ],
);

Future<void> _pumpWithRouter(
  WidgetTester tester,
  ProviderContainer container,
) async {
  _setSize(tester, _desktop);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: _router(container),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field() => find.descendant(
  of: find.byType(DesktopSearchField),
  matching: find.byType(TextField),
);

double _dy(WidgetTester tester, Finder finder) => tester.getCenter(finder).dy;

void main() {
  group('desktop Settings search section', () {
    testWidgets('typing "theme" shows Settings with App Theme Mode', (
      tester,
    ) async {
      await _pumpWithRouter(tester, await _container());

      await tester.enterText(_field(), 'theme');
      await tester.pump();
      await tester.pump();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('App Theme Mode'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Appearance › Theme'), findsOneWidget);
      // No Go to hits for "theme": only Settings above Search all sources.
      expect(find.text('Go to'), findsNothing);
      expect(
        _dy(tester, find.text('Settings')),
        lessThan(_dy(tester, find.text('Search all sources for "theme"'))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Settings sits between Go to and Search all sources', (
      tester,
    ) async {
      // "upd" hits all four bands with few rows (Library, Updates, three
      // settings, Search all sources) so the whole dropdown builds at once.
      await _pumpWithRouter(
        tester,
        await _container(library: [_manga(2, 'Update Notes')]),
      );

      await tester.enterText(_field(), 'upd');
      await tester.pump();
      await tester.pump();

      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Go to'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Automatic Update'), findsOneWidget);
      // The dropdown scrolls: locate rows including below-the-fold ones.
      Finder shown(String text) => find.text(text, skipOffstage: false);
      final lib = _dy(tester, shown('Library').first);
      final goTo = _dy(tester, shown('Go to'));
      final settings = _dy(tester, shown('Settings'));
      final all = _dy(tester, shown('Search all sources for "upd"'));
      expect(lib, lessThan(goTo));
      expect(goTo, lessThan(settings));
      expect(settings, lessThan(all));
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking a row opens the page with the highlight id', (
      tester,
    ) async {
      final container = await _container();
      await _pumpWithRouter(tester, container);

      await tester.enterText(_field(), 'theme');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('App Theme Mode'));
      await tester.pumpAndSettle();

      expect(
        find.text('SETTINGS appearance highlight=appThemeMode'),
        findsOneWidget,
      );
      expect(
        container.read(unifiedSearchQueryProvider),
        isEmpty,
        reason: 'leaving through a result clears the query',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Enter opens the first setting when only settings match', (
      tester,
    ) async {
      final container = await _container();
      await _pumpWithRouter(tester, container);

      await tester.enterText(_field(), 'theme');
      await tester.pump();
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        find.text('SETTINGS appearance highlight=appThemeMode'),
        findsOneWidget,
      );
      expect(container.read(unifiedSearchQueryProvider), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Enter still prefers Go to over settings', (tester) async {
      await _pumpWithRouter(tester, await _container());

      await tester.enterText(_field(), 'upd');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('UPDATES PAGE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
