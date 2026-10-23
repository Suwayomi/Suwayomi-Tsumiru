// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/browse_center/presentation/global_search/controller/source_quick_search_controller.dart';
import 'package:tsumiru/src/features/browse_center/presentation/global_search/global_search_screen.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/controller/source_controller.dart';
import 'package:tsumiru/src/features/hotkeys/presentation/global_shortcut_host.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_repository.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/chapter_list_entry.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/next_update_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/manga_details_screen.dart';
import 'package:tsumiru/src/features/manga_book/presentation/recommends/recommends_screen.dart';
import 'package:tsumiru/src/features/manga_book/widgets/chapter_actions/multi_chapters_actions_bottom_app_bar.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/widgets/shell/detail_navigation_shell_screen.dart';

ChapterDto _chapter({required int id, bool read = false}) => ChapterDto(
  chapterNumber: id.toDouble(),
  fetchedAt: '0',
  id: id,
  mangaId: 1,
  name: 'Chapter $id',
  pageCount: 20,
  realUrl: null,
  scanlator: 'Group A',
  sourceOrder: id,
  uploadDate: '0',
  url: '',
  meta: const [],
  user: Fragment$ChapterDto$user(
    isBookmarked: false,
    isDownloaded: false,
    isRead: read,
    lastPageRead: 0,
    lastReadAt: read ? '1' : '0',
  ),
);

final _chapters = [
  _chapter(id: 1, read: true),
  _chapter(id: 2),
  _chapter(id: 3),
];

final _manga = MangaDto.fromJson({
  '__typename': 'MangaType',
  'id': 1,
  'title': 'Test series',
  'author': 'An author',
  'user': {
    '__typename': 'MangaUserType',
    'bookmarkCount': 0,
    'downloadCount': 0,
    'inLibrary': true,
    'inLibraryAt': '0',
    'unreadCount': 2,
  },
  'chapters': {'totalCount': 3, '__typename': 'ChapterNodeList'},
  'genre': ['Action'],
  'initialized': true,
  'meta': [],
  'sourceId': '0',
  'status': 'ONGOING',
  'categories': {'nodes': [], '__typename': 'CategoryNodeList'},
  'trackRecords': {'nodes': [], '__typename': 'TrackRecordNodeList'},
  'updateStrategy': 'ALWAYS_UPDATE',
  'url': '',
});

class _Manga extends MangaWithId {
  @override
  Future<MangaDto?> build({required int mangaId}) async => _manga;
  @override
  Future<void> refresh([bool onlineFetch = false]) async {}
}

class _Chapters extends MangaChapterList {
  @override
  Future<List<ChapterDto>?> build({required int mangaId}) async => _chapters;
  @override
  Future<void> refresh([bool onlineFetch = false]) async {}
}

class _Scope extends GlobalSearchScope {
  @override
  GlobalSearchSourceFilter? build() => GlobalSearchSourceFilter.all;
}

/// The app's route shape around the detail shell: quick-open shell → stateful
/// navigation shell (stubbed Library) + [DetailNavigationShellRoute]. Only the
/// screens the back behaviour needs are real.
GoRouter _router({String location = '/library/0'}) => GoRouter(
  initialLocation: location,
  routes: [
    ShellRoute(
      builder: (context, state, child) => GlobalShortcutHost(child: child),
      routes: [
        GoRoute(
          path: Routes.library,
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => MangaRoute(mangaId: 1).push(context),
                child: const Text('LIBRARY'),
              ),
            ),
          ),
        ),
        ShellRoute(
          builder: (context, state, child) =>
              DetailNavigationShellScreen(child: child),
          routes: [
            GoRoute(
              path: Routes.mangaRoute,
              builder: (context, state) => MangaDetailsScreen(
                mangaId: int.parse(state.pathParameters['mangaId']!),
                categoryId: int.tryParse(
                  state.uri.queryParameters['category-id'] ?? '',
                ),
              ),
            ),
            GoRoute(
              path: Routes.recommends,
              builder: (context, state) =>
                  const RecommendsScreen(mangaId: 1, mangaTitle: 'Test series'),
            ),
            GoRoute(
              path: Routes.globalSearch,
              builder: (context, state) => const GlobalSearchScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

Future<GoRouter> _pump(
  WidgetTester tester,
  Size size, {
  String location = '/library/0',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final router = _router(location: location);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        offlineEnabledProvider.overrideWithValue(false),
        downloadsPausedBadgeProvider.overrideWith((ref) => false),
        extensionUpdateBadgeCountProvider.overrideWith((ref) async => 0),
        failedUpdatesProvider.overrideWith((ref) async => []),
        mangaWithIdProvider(mangaId: 1).overrideWith(_Manga.new),
        mangaChapterListProvider(mangaId: 1).overrideWith(_Chapters.new),
        mangaChapterListWithFilterProvider(
          mangaId: 1,
        ).overrideWith((ref) => AsyncData(_chapters)),
        mangaChapterListEntriesProvider(mangaId: 1).overrideWith(
          (ref) => AsyncData([for (final c in _chapters) MangaChapterEntry(c)]),
        ),
        firstUnreadInFilteredChapterListProvider(
          mangaId: 1,
        ).overrideWith((ref) => _chapters[1]),
        mangaNextUpdateProvider(mangaId: 1).overrideWith((ref) => null),
        recommendationSetupProvider(1).overrideWith((ref) async => null),
        pinnedSourcesProvider.overrideWith((ref) => const <SourceDto>[]),
        globalSearchScopeProvider.overrideWith(_Scope.new),
        quickSearchResultsProvider(
          query: null,
        ).overrideWith((ref) => AsyncData(const <QuickSearchResults>[])),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _openSeriesFromLibrary(WidgetTester tester) async {
  await tester.tap(find.text('LIBRARY'));
  await tester.pumpAndSettle();
  expect(find.byType(MangaDetailsScreen), findsOneWidget);
}

void main() {
  testWidgets('every back path returns to the right page', (tester) async {
    final router = await _pump(tester, const Size(412, 915));
    await _openSeriesFromLibrary(tester);

    // In-app back from recommends returns to the series.
    router.push(const RecommendsRoute(mangaId: 1).location);
    await tester.pumpAndSettle();
    expect(find.byType(RecommendsScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(MangaDetailsScreen), findsOneWidget);
    expect(find.text('LIBRARY'), findsNothing);

    // In-app back from global search returns to the series.
    router.push(const GlobalSearchRoute().location);
    await tester.pumpAndSettle();
    expect(find.byType(GlobalSearchScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(MangaDetailsScreen), findsOneWidget);
    expect(find.text('LIBRARY'), findsNothing);

    // Esc clears a phone selection even while an app bar action has focus.
    await tester.longPress(find.text('Chapter 2'));
    await tester.pumpAndSettle();
    expect(find.byType(MultiChaptersActionsBottomAppBar), findsOneWidget);
    final phoneSelectAll = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.select_all_rounded),
    );
    final phoneNode = Focus.of(tester.element(phoneSelectAll));
    phoneNode.requestFocus();
    await tester.pump();
    expect(phoneNode.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MultiChaptersActionsBottomAppBar), findsNothing);
    expect(find.byType(MangaDetailsScreen), findsOneWidget);

    // System back returns to the library.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('LIBRARY'), findsOneWidget);
    expect(find.byType(MangaDetailsScreen), findsNothing);

    // At desktop width, Esc clears a selection even while a header button has
    // focus, then Esc again leaves the series.
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    await _openSeriesFromLibrary(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Chapter 2'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsWidgets);
    final headerSelectAll = find.descendant(
      of: find.byKey(const ValueKey('chapterSelectionHeader')),
      matching: find.byIcon(Icons.select_all_rounded),
    );
    final headerNode = Focus.of(tester.element(headerSelectAll));
    headerNode.requestFocus();
    await tester.pump();
    expect(headerNode.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(MangaDetailsScreen), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('LIBRARY'), findsOneWidget);
    expect(find.byType(MangaDetailsScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a deep link straight to a series shows no back button', (
    tester,
  ) async {
    await _pump(tester, const Size(412, 915), location: '/manga/1');
    expect(find.byType(MangaDetailsScreen), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });
}
