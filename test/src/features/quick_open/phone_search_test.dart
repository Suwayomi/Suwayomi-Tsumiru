// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Slice 4b: phone pages get a visible search entry opening a full-screen
// overlay. Typing there never touches the page until the page row is applied;
// leaving through a result clears the search text.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/controller/source_controller.dart';
import 'package:tsumiru/src/features/history/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/history/domain/history_item.dart';
import 'package:tsumiru/src/features/history/presentation/history_controller.dart';
import 'package:tsumiru/src/features/history/presentation/history_screen.dart';
import 'package:tsumiru/src/features/library/data/default_category.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/library/presentation/library/library_screen.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/phone_search_view.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/data/syncyomi_settings_provider.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/cover_row_section.dart';
import 'package:tsumiru/src/widgets/search_field.dart';

const _phone = Size(412, 900);
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

Fragment$HistoryChapterDto _historyItem({
  required int id,
  required String series,
  required String chapter,
}) => Fragment$HistoryChapterDto(
  id: id,
  chapterNumber: 1,
  fetchedAt: '0',
  isBookmarked: false,
  isDownloaded: false,
  isRead: false,
  lastPageRead: 4,
  lastReadAt: '1700000000',
  mangaId: id,
  name: chapter,
  pageCount: 10,
  sourceOrder: 1,
  uploadDate: '0',
  url: '/c/$id',
  meta: const [],
  manga: Fragment$HistoryChapterDto$manga(
    id: id,
    inLibrary: true,
    title: series,
    unreadCount: 3,
  ),
);

Fragment$SourceDto _source(String id, String name) => Fragment$SourceDto(
  displayName: name,
  iconUrl: '',
  id: id,
  isConfigurable: false,
  contentWarning: Enum$ContentWarning.SAFE,
  lang: 'en',
  name: name,
  supportsLatest: false,
  meta: const [],
  $extension: Fragment$SourceDto$extension(
    pkgName: 'pkg.$id',
    isObsolete: false,
  ),
);

Fragment$CategoryDto _category(int id, String name) => Fragment$CategoryDto(
  defaultCategory: false,
  id: id,
  includeInDownload: Enum$IncludeOrExclude.UNSET,
  includeInUpdate: Enum$IncludeOrExclude.UNSET,
  name: name,
  order: id,
  mangas: Fragment$CategoryDto$mangas(totalCount: 0),
  meta: const [],
);

const _emptyCategories = AsyncData(<Fragment$CategoryDto>[]);

class _FakeReadingHistory extends ReadingHistory {
  _FakeReadingHistory(this.items);

  final List<HistoryItemDto> items;

  @override
  Future<List<HistoryItemDto>?> build() async => items;
}

Finder _overlayField() => find.descendant(
  of: find.byType(PhoneSearchOverlay),
  matching: find.byType(TextField),
);

/// Pumps a bare search entry at phone size. Tests open the overlay by tapping
/// the icon, so the overlay behaviour is covered without pumping whole pages.
Future<ProviderContainer> _pumpEntry(
  WidgetTester tester, {
  required PhoneSearchOrigin origin,
  List<Fragment$MangaDto> library = const [],
  List<HistoryItemDto> history = const [],
  Map<String, List<Fragment$SourceDto>>? sources,
}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      libraryMangaListProvider.overrideWith((ref) async => library),
      visibleCategoryListProvider.overrideWithValue(_emptyCategories),
      readingHistoryProvider.overrideWith(() => _FakeReadingHistory(history)),
      if (sources != null)
        sourceMapFilteredProvider.overrideWithValue(AsyncData(sources)),
    ],
  );
  addTearDown(container.dispose);
  _setSize(tester, _phone);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(child: PhoneSearchEntry(origin: origin)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _openOverlay(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.search_rounded));
  await tester.pumpAndSettle();
  expect(find.byType(PhoneSearchOverlay), findsOneWidget);
}

Future<ProviderContainer> _pumpEntryWithRouter(
  WidgetTester tester, {
  required PhoneSearchOrigin origin,
  List<Fragment$MangaDto> library = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      libraryMangaListProvider.overrideWith((ref) async => library),
      visibleCategoryListProvider.overrideWithValue(_emptyCategories),
      readingHistoryProvider.overrideWith(() => _FakeReadingHistory(const [])),
    ],
  );
  addTearDown(container.dispose);
  _setSize(tester, _phone);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Scaffold(
                body: Center(child: PhoneSearchEntry(origin: origin)),
              ),
            ),
            GoRoute(
              path: '/updates',
              builder: (_, _) =>
                  const Scaffold(body: Center(child: Text('UPDATES PAGE'))),
            ),
            GoRoute(
              path: '/manga/:mangaId',
              builder: (_, _) =>
                  const Scaffold(body: Center(child: Text('MANGA PAGE'))),
            ),
            GoRoute(
              path: '/library/:categoryId',
              builder: (_, _) =>
                  const Scaffold(body: Center(child: Text('LIBRARY PAGE'))),
            ),
            GoRoute(
              path: '/global-search',
              builder: (_, _) => const Scaffold(
                body: Center(child: Text('GLOBAL SEARCH PAGE')),
              ),
            ),
          ],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Pumps the real LibraryScreen at phone size, with or without the persistent
/// search setting.
Future<ProviderContainer> _pumpLibrary(
  WidgetTester tester, {
  bool persistent = false,
  List<Fragment$MangaDto> library = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    if (persistent) 'libraryPersistentSearchBar': true,
  });
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      loggedInTrackersProvider.overrideWithValue(
        const AsyncData(<Fragment$TrackerDto>[]),
      ),
      updateRunningSocketProvider.overrideWithValue(
        const AsyncData<bool?>(null),
      ),
      failedUpdateCountProvider.overrideWithValue(const AsyncData(0)),
      syncYomiSettingsProvider.overrideWithValue(const AsyncData(null)),
      settledDefaultCategoryIdProvider.overrideWithValue(1),
      nonZeroCategoryListProvider.overrideWithValue(
        AsyncData([_category(1, 'One'), _category(2, 'Two')]),
      ),
      visibleCategoryListProvider.overrideWithValue(
        AsyncData([_category(1, 'One'), _category(2, 'Two')]),
      ),
      libraryMangaListProvider.overrideWith((ref) async => library),
      categoryMangaListProvider.overrideWith(
        (ref, categoryId) async => <Fragment$MangaDto>[],
      ),
      categoryMangaListWithQueryAndFilterProvider(
        categoryId: 1,
      ).overrideWithValue(AsyncData<List<Fragment$MangaDto>?>(null)),
      categoryMangaListWithQueryAndFilterProvider(
        categoryId: 2,
      ).overrideWithValue(AsyncData<List<Fragment$MangaDto>?>(null)),
    ],
  );
  addTearDown(container.dispose);
  _setSize(tester, _phone);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LibraryScreen(categoryId: 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Pumps the real HistoryScreen, phone or desktop, with or without the
/// persistent search setting.
Future<ProviderContainer> _pumpHistory(
  WidgetTester tester, {
  required Size size,
  bool persistent = false,
}) async {
  SharedPreferences.setMockInitialValues({
    if (persistent) 'libraryPersistentSearchBar': true,
  });
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      readingHistoryProvider.overrideWith(() => _FakeReadingHistory(const [])),
      libraryMangaListProvider.overrideWith((ref) async => const []),
      visibleCategoryListProvider.overrideWithValue(_emptyCategories),
    ],
  );
  addTearDown(container.dispose);
  _setSize(tester, size);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: HistoryScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('phone search overlay', () {
    testWidgets('search icon opens the full-screen view', (tester) async {
      await _pumpEntry(tester, origin: PhoneSearchOrigin.library);
      await _openOverlay(tester);

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      final field = tester.widget<TextField>(_overlayField());
      expect(field.autofocus, isTrue);
      expect(
        field.decoration?.hintText,
        'Search your library, app, and sources',
      );
      // Empty query teaches the operators, like the unified search.
      expect(find.text('unread:true'), findsOneWidget);
    });

    testWidgets('typing does not change the page filter', (tester) async {
      final container = await _pumpEntry(
        tester,
        origin: PhoneSearchOrigin.library,
        library: [_manga(1, 'Sword Chronicles')],
      );
      await _openOverlay(tester);

      await tester.enterText(_overlayField(), 'sw');
      await tester.pump();
      await tester.pump();

      expect(find.text('Search library for "sw"'), findsOneWidget);
      expect(
        container.read(libraryQueryProvider),
        isNull,
        reason: 'typing must not filter the page underneath',
      );
    });

    testWidgets('page row applies q and closes', (tester) async {
      final container = await _pumpEntry(
        tester,
        origin: PhoneSearchOrigin.library,
        library: [_manga(1, 'Sword Chronicles')],
      );
      await _openOverlay(tester);

      await tester.enterText(_overlayField(), 'sw');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Search library for "sw"'));
      await tester.pumpAndSettle();

      expect(container.read(libraryQueryProvider), 'sw');
      expect(find.byType(PhoneSearchOverlay), findsNothing);
    });

    testWidgets('Enter applies the page row', (tester) async {
      final container = await _pumpEntry(
        tester,
        origin: PhoneSearchOrigin.history,
        history: [
          _historyItem(
            id: 1,
            series: 'Sword Chronicles',
            chapter: 'Chapter 12',
          ),
        ],
      );
      await _openOverlay(tester);

      await tester.enterText(_overlayField(), 'sw');
      await tester.pump();
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(container.read(historySearchQueryProvider), 'sw');
      expect(find.byType(PhoneSearchOverlay), findsNothing);
    });

    testWidgets('dimmed No results row is not tappable', (tester) async {
      final container = await _pumpEntry(
        tester,
        origin: PhoneSearchOrigin.library,
      );
      await _openOverlay(tester);

      await tester.enterText(_overlayField(), 'zzz');
      await tester.pump();

      expect(find.text('Search library for "zzz"'), findsOneWidget);
      expect(find.text('No results'), findsOneWidget);
      await tester.tap(find.text('Search library for "zzz"'));
      await tester.pump();

      expect(
        container.read(libraryQueryProvider),
        isNull,
        reason: 'a dimmed row must not apply anything',
      );
      expect(
        find.byType(PhoneSearchOverlay),
        findsOneWidget,
        reason: 'a dimmed row must not close the view',
      );
    });

    testWidgets('operator query passes through unchanged', (tester) async {
      final container = await _pumpEntry(
        tester,
        origin: PhoneSearchOrigin.library,
        library: [_manga(1, 'Sword Chronicles')],
      );
      await _openOverlay(tester);

      await tester.enterText(_overlayField(), 'unread:true');
      await tester.pump();
      await tester.tap(find.text('Search library for "unread:true"'));
      await tester.pumpAndSettle();

      expect(container.read(libraryQueryProvider), 'unread:true');
    });
  });

  group('history origin', () {
    final items = [
      _historyItem(id: 1, series: 'Sword One', chapter: 'Chapter 12'),
      _historyItem(id: 2, series: 'Sword Two', chapter: 'Chapter 11'),
      _historyItem(id: 3, series: 'Sword Three', chapter: 'Chapter 10'),
      _historyItem(id: 4, series: 'Sword Four', chapter: 'Chapter 9'),
    ];

    testWidgets('History row, then up to 3 entries, then Library rows', (
      tester,
    ) async {
      await _pumpEntry(
        tester,
        origin: PhoneSearchOrigin.history,
        history: items,
        library: [_manga(1, 'Sword Chronicles')],
      );
      await _openOverlay(tester);

      await tester.enterText(_overlayField(), 'sw');
      await tester.pump();
      await tester.pump();

      expect(find.text('Search history for "sw"'), findsOneWidget);
      expect(find.textContaining('Chapter 12'), findsOneWidget);
      expect(find.textContaining('Chapter 11'), findsOneWidget);
      expect(find.textContaining('Chapter 10'), findsOneWidget);
      expect(
        find.textContaining('Chapter 9'),
        findsNothing,
        reason: 'only the first 3 page matches show',
      );
      // Library matches are list rows (title + unread) on other pages.
      expect(find.text('Sword Chronicles'), findsOneWidget);
      expect(find.text('2 unread'), findsOneWidget);

      double top(Finder f) => tester.getTopLeft(f).dy;
      expect(
        top(find.text('Search history for "sw"')),
        lessThan(top(find.textContaining('Chapter 12'))),
      );
      expect(
        top(find.textContaining('Chapter 12')),
        lessThan(top(find.text('Sword Chronicles'))),
      );
    });
  });

  group('library origin', () {
    testWidgets('Library section is a horizontal cover row', (tester) async {
      await _pumpEntry(
        tester,
        origin: PhoneSearchOrigin.library,
        library: [_manga(1, 'Sword Chronicles')],
      );
      await _openOverlay(tester);

      await tester.enterText(_overlayField(), 'sw');
      await tester.pump();
      await tester.pump();

      expect(find.byType(CoverRowSection), findsOneWidget);
      expect(find.text('Sword Chronicles'), findsOneWidget);
      // No list-style unread line under the cover row.
      expect(find.text('2 unread'), findsNothing);
    });

    testWidgets('leaving through a cover clears the search text', (
      tester,
    ) async {
      final container = await _pumpEntryWithRouter(
        tester,
        origin: PhoneSearchOrigin.library,
        library: [_manga(1, 'Sword Chronicles')],
      );
      await _openOverlay(tester);

      await tester.enterText(_overlayField(), 'sw');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Sword Chronicles'));
      await tester.pumpAndSettle();

      expect(find.text('MANGA PAGE'), findsOneWidget);
      expect(
        container.read(libraryQueryProvider),
        isNull,
        reason: 'leaving through a result clears the search text',
      );
    });
  });

  group('leaving through results', () {
    testWidgets('Go to navigates and clears the search text', (tester) async {
      final container = await _pumpEntryWithRouter(
        tester,
        origin: PhoneSearchOrigin.plain,
      );
      await _openOverlay(tester);

      await tester.enterText(_overlayField(), 'upd');
      await tester.pump();
      expect(find.text('Go to'), findsOneWidget);
      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();

      expect(find.text('UPDATES PAGE'), findsOneWidget);
      expect(container.read(libraryQueryProvider), isNull);
      expect(container.read(historySearchQueryProvider), isEmpty);
    });

    testWidgets('Search all sources navigates', (tester) async {
      await _pumpEntryWithRouter(tester, origin: PhoneSearchOrigin.plain);
      await _openOverlay(tester);

      await tester.enterText(_overlayField(), 'sw');
      await tester.pump();
      await tester.tap(find.text('Search all sources for "sw"'));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH PAGE'), findsOneWidget);
    });
  });

  group('sources origin', () {
    Map<String, List<Fragment$SourceDto>> sources() => {
      'en': [
        _source('1', 'Swag Scans'),
        _source('2', 'Swift Scans'),
        _source('3', 'Sword Scans'),
        _source('4', 'Swamp Scans'),
      ],
    };

    testWidgets('Sources row, then up to 3 source matches', (tester) async {
      await _pumpEntry(
        tester,
        origin: PhoneSearchOrigin.sources,
        sources: sources(),
      );
      await _openOverlay(tester);

      await tester.enterText(_overlayField(), 'sw');
      await tester.pump();
      await tester.pump();

      expect(find.text('Search sources for "sw"'), findsOneWidget);
      expect(find.text('Swag Scans'), findsOneWidget);
      expect(find.text('Swift Scans'), findsOneWidget);
      expect(find.text('Sword Scans'), findsOneWidget);
      expect(
        find.text('Swamp Scans'),
        findsNothing,
        reason: 'only the first 3 page matches show',
      );
    });

    testWidgets('Sources row applies q to the source filter', (tester) async {
      final container = await _pumpEntry(
        tester,
        origin: PhoneSearchOrigin.sources,
        sources: sources(),
      );
      await _openOverlay(tester);

      await tester.enterText(_overlayField(), 'sw');
      await tester.pump();
      await tester.pump();
      // Nothing matches until the row is applied.
      expect(container.read(sourceSearchQueryProvider), isNull);
      await tester.tap(find.text('Search sources for "sw"'));
      await tester.pumpAndSettle();

      expect(container.read(sourceSearchQueryProvider), 'sw');
      expect(find.byType(PhoneSearchOverlay), findsNothing);
    });
  });

  group('library page entry', () {
    testWidgets('phone shows the search icon, which opens the view', (
      tester,
    ) async {
      final container = await _pumpLibrary(
        tester,
        library: [_manga(1, 'Sword Chronicles')],
      );
      expect(tester.takeException(), isNull);

      expect(find.byType(PhoneSearchEntry), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(SearchField),
        ),
        findsNothing,
        reason: 'the old in-app-bar field is replaced by the flow',
      );

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneSearchOverlay), findsOneWidget);

      await tester.enterText(_overlayField(), 'sw');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Search library for "sw"'));
      await tester.pumpAndSettle();

      expect(container.read(libraryQueryProvider), 'sw');
      expect(find.byType(PhoneSearchOverlay), findsNothing);
    });

    testWidgets('persistent setting shows the box instead of the icon', (
      tester,
    ) async {
      await _pumpLibrary(tester, persistent: true);
      expect(tester.takeException(), isNull);

      expect(find.byType(PhoneSearchBoxBottom), findsOneWidget);
      expect(
        find.text('Search your library, app, and sources'),
        findsOneWidget,
      );
      expect(
        find.widgetWithIcon(IconButton, Icons.search_rounded),
        findsNothing,
        reason: 'no search icon when the box shows',
      );

      await tester.tap(find.text('Search your library, app, and sources'));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneSearchOverlay), findsOneWidget);
    });
  });

  group('history page entry', () {
    testWidgets('phone shows the search icon and no inline field', (
      tester,
    ) async {
      await _pumpHistory(tester, size: _phone);
      expect(tester.takeException(), isNull);

      expect(find.byType(PhoneSearchEntry), findsOneWidget);
      expect(find.byType(SearchField), findsNothing);

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneSearchOverlay), findsOneWidget);
    });

    testWidgets('persistent setting shows the box instead of the icon', (
      tester,
    ) async {
      await _pumpHistory(tester, size: _phone, persistent: true);
      expect(tester.takeException(), isNull);

      expect(find.byType(PhoneSearchBoxBottom), findsOneWidget);
      expect(
        find.widgetWithIcon(IconButton, Icons.search_rounded),
        findsNothing,
        reason: 'no search icon when the box shows',
      );
    });

    testWidgets('desktop is unchanged', (tester) async {
      await _pumpHistory(tester, size: _desktop);
      expect(tester.takeException(), isNull);

      expect(find.byType(PhoneSearchEntry), findsNothing);
      expect(find.byType(PhoneSearchBoxBottom), findsNothing);
      expect(find.byType(SearchField), findsNothing);
    });
  });
}
