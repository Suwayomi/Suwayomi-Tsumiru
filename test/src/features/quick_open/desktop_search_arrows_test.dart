// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Arrow-key navigation in the desktop search dropdown: Up/Down move a
// highlight across every section in visual order, Enter opens the
// highlighted row exactly as a tap would, and typing resets the highlight.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  chapters: Fragment$MangaDto$chapters(totalCount: 4),
  genre: const [],
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/$id',
  user: Fragment$MangaDto$user(
    bookmarkCount: 0,
    downloadCount: 1,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: 2,
  ),
);

const _emptyCategories = AsyncData(<Fragment$CategoryDto>[]);

// Reachable server, so the server-gated Settings rows render like on their
// pages (same overrides as the settings-search tests).
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

GoRouter _router() => GoRouter(
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
    GoRoute(
      path: '/manga/:mangaId',
      builder: (_, state) => Scaffold(
        body: Center(child: Text('MANGA ${state.pathParameters['mangaId']}')),
      ),
    ),
    GoRoute(
      path: '/global-search',
      builder: (_, _) =>
          const Scaffold(body: Center(child: Text('GLOBAL SEARCH PAGE'))),
    ),
    GoRoute(
      path: '/more/settings/library',
      builder: (_, state) => Scaffold(
        body: Center(
          child: Text(
            'SETTINGS library highlight=${state.uri.queryParameters['highlight']}',
          ),
        ),
      ),
    ),
  ],
);

Future<void> _pumpWithRouter(
  WidgetTester tester,
  ProviderContainer container, {
  Size size = _desktop,
}) async {
  _setSize(tester, size);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: _router(),
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

Future<void> _down(WidgetTester tester, [int n = 1]) async {
  for (var i = 0; i < n; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
  }
}

Future<void> _submit(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

// "upd" hits Library, Go to, Settings, and Search all sources with few rows.
Future<void> _typeUpd(WidgetTester tester) async {
  await tester.enterText(_field(), 'upd');
  await tester.pump();
  await tester.pump();
}

// The highlight paints the row's hover colour, so the highlighted row is the
// ancestor Material wearing it. (Semantics flags live on ancestor nodes and
// don't merge down into the row's Text, so colour is the row-identity check;
// the selected flag itself is covered by [_treeHasSelected].)
bool _isHighlighted(WidgetTester tester, Finder text) {
  final hover = Theme.of(tester.element(text)).hoverColor;
  return tester
      .widgetList<Material>(
        find.ancestor(of: text, matching: find.byType(Material)),
      )
      .any((m) => m.color == hover);
}

void main() {
  group('desktop search arrow-key navigation', () {
    testWidgets('Down, Down, Enter opens the second row', (tester) async {
      final container = await _container(library: [_manga(2, 'Update Notes')]);
      await _pumpWithRouter(tester, container);

      await _typeUpd(tester);
      expect(find.text('Updates'), findsOneWidget);

      await _down(tester, 2);
      expect(_isHighlighted(tester, find.text('Updates')), isTrue);
      await _submit(tester);

      expect(find.text('UPDATES PAGE'), findsOneWidget);
      expect(
        container.read(unifiedSearchQueryProvider),
        isEmpty,
        reason: 'leaving through a result clears the query',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
