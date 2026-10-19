// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Slice 4a: every desktop page shows a DesktopSearchField in its header that
// opens the unified results as a dropdown.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/history/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/history/domain/history_group.dart';
import 'package:tsumiru/src/features/history/domain/history_item.dart';
import 'package:tsumiru/src/features/history/presentation/history_controller.dart';
import 'package:tsumiru/src/features/history/presentation/history_screen.dart';
import 'package:tsumiru/src/features/hotkeys/presentation/global_shortcut_host.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/desktop_library_toolbar.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/quick_open/presentation/search_stack/search_stack_screen.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/desktop_search_field.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/phone_search_view.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_providers.dart';
import 'package:tsumiru/src/features/settings/presentation/general/quick_search_toggle/quick_search_toggle_tile.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/search_field.dart';

import '../../../helpers/unreachable_server_stubs.dart';

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

/// The library list + (empty) visible categories every DesktopSearchField pump
/// needs so it never hits the network. Inlined at each call site so the list
/// literal takes its type from the `overrides:` parameter.
const _emptyCategories = AsyncData(<Fragment$CategoryDto>[]);

/// Standalone field bound to the unified query, as Updates/Browse/Downloads/
/// More mount it.
Widget _boundField() => Consumer(
  builder: (context, ref, _) => DesktopSearchField(
    query: ref.watch(unifiedSearchQueryProvider),
    onChanged: (value) =>
        ref.read(unifiedSearchQueryProvider.notifier).state = value,
    onNavigate: () => ref.read(unifiedSearchQueryProvider.notifier).state = '',
  ),
);

Finder _fieldTextField() => find.descendant(
  of: find.byType(DesktopSearchField),
  matching: find.byType(TextField),
);

Future<ProviderContainer> _pumpField(
  WidgetTester tester, {
  List<Fragment$MangaDto> library = const [],
}) async {
  _setSize(tester, _desktop);
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      libraryMangaListProvider.overrideWith((ref) async => library),
      visibleCategoryListProvider.overrideWithValue(_emptyCategories),
      ...unreachableServerStubs,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(child: SizedBox(width: 500, child: _boundField())),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

GoRouter _routerWithField(List<Fragment$MangaDto> library) => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => Scaffold(
        body: Center(child: SizedBox(width: 500, child: _boundField())),
      ),
    ),
    GoRoute(
      path: '/updates',
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('UPDATES PAGE'))),
    ),
    GoRoute(
      path: '/library/:categoryId',
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('LIBRARY PAGE'))),
    ),
    GoRoute(
      path: '/manga/:mangaId',
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('MANGA PAGE'))),
    ),
    GoRoute(
      path: '/global-search',
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('GLOBAL SEARCH PAGE'))),
    ),
  ],
);

Future<ProviderContainer> _pumpFieldWithRouter(
  WidgetTester tester, {
  List<Fragment$MangaDto> library = const [],
}) async {
  _setSize(tester, _desktop);
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      libraryMangaListProvider.overrideWith((ref) async => library),
      visibleCategoryListProvider.overrideWithValue(_emptyCategories),
      ...unreachableServerStubs,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: _routerWithField(library),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

class _ToggleOn extends QuickSearchToggle {
  @override
  bool? build() => true;
}

class _FakeReadingHistory extends ReadingHistory {
  _FakeReadingHistory(this.items);

  final List<HistoryItemDto> items;

  @override
  Future<List<HistoryItemDto>?> build() async => items;
}

void main() {
  group('DesktopSearchField', () {
    testWidgets('shows the unified hint', (tester) async {
      await _pumpField(tester);
      expect(tester.takeException(), isNull);
      final field = tester.widget<TextField>(_fieldTextField());
      expect(
        field.decoration?.hintText,
        'Search your library, app, and sources',
      );
    });

    testWidgets('text is vertically centred in the 40 px box', (tester) async {
      await _pumpField(tester);
      expect(tester.takeException(), isNull);

      final box = tester.getRect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.clipBehavior == Clip.antiAlias &&
              (w.decoration as BoxDecoration?)?.borderRadius ==
                  BorderRadius.circular(10),
        ),
      );
      expect(box.height, 40);
      final textCenter = tester.getCenter(
        find.descendant(
          of: find.byType(DesktopSearchField),
          matching: find.byType(EditableText),
        ),
      );
      expect((textCenter.dy - box.center.dy).abs(), lessThanOrEqualTo(1));
    });

    testWidgets('typing opens Library hits and Search all sources', (
      tester,
    ) async {
      await _pumpField(tester, library: [_manga(1, 'Sword Chronicles')]);

      await tester.enterText(_fieldTextField(), 'sw');
      // The dropdown's first watch starts the library future; its completion
      // lands a frame later.
      await tester.pump();
      await tester.pump();

      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Sword Chronicles'), findsOneWidget);
      expect(find.text('2 unread'), findsOneWidget);
      expect(find.text('Search all sources for "sw"'), findsOneWidget);
    });

    testWidgets('Esc closes the dropdown; Esc again clears the query', (
      tester,
    ) async {
      final container = await _pumpField(
        tester,
        library: [_manga(1, 'Sword Chronicles')],
      );

      await tester.enterText(_fieldTextField(), 'sw');
      await tester.pump();
      expect(find.text('Search all sources for "sw"'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        find.text('Search all sources for "sw"'),
        findsNothing,
        reason: 'first Esc closes the dropdown',
      );
      expect(
        container.read(unifiedSearchQueryProvider),
        'sw',
        reason: 'closing keeps the text',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        container.read(unifiedSearchQueryProvider),
        isEmpty,
        reason: 'second Esc clears',
      );
    });

    testWidgets('Enter opens the top library hit and clears the query', (
      tester,
    ) async {
      final container = await _pumpFieldWithRouter(
        tester,
        library: [_manga(1, 'Sword Chronicles')],
      );

      await tester.enterText(_fieldTextField(), 'sw');
      await tester.pump();
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('MANGA PAGE'), findsOneWidget);
      expect(
        container.read(unifiedSearchQueryProvider),
        isEmpty,
        reason: 'leaving through a result clears the query',
      );
    });

    testWidgets('picking a Go to target clears the query', (tester) async {
      final container = await _pumpFieldWithRouter(tester);

      await tester.enterText(_fieldTextField(), 'upd');
      await tester.pump();
      expect(find.text('Go to'), findsOneWidget);
      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();

      expect(find.text('UPDATES PAGE'), findsOneWidget);
      expect(
        container.read(unifiedSearchQueryProvider),
        isEmpty,
        reason: 'leaving through a result clears the query',
      );
    });

    testWidgets('Search all sources navigates and clears the query', (
      tester,
    ) async {
      final container = await _pumpFieldWithRouter(tester);

      await tester.enterText(_fieldTextField(), 'sw');
      await tester.pump();
      await tester.tap(find.text('Search all sources for "sw"'));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH PAGE'), findsOneWidget);
      expect(container.read(unifiedSearchQueryProvider), isEmpty);
    });

    testWidgets('Ctrl+F focuses the field instead of opening the overlay', (
      tester,
    ) async {
      _setSize(tester, _desktop);
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          quickSearchToggleProvider.overrideWith(_ToggleOn.new),
          libraryMangaListProvider.overrideWith((ref) async => null),
          visibleCategoryListProvider.overrideWithValue(_emptyCategories),
          ...unreachableServerStubs,
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GlobalShortcutHost(
              child: Scaffold(
                body: Center(child: SizedBox(width: 500, child: _boundField())),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(
        container.read(quickOpenVisibleProvider),
        isFalse,
        reason: 'the field takes Ctrl+F, not the overlay',
      );
      final node = container.read(desktopSearchFocusNodeProvider);
      expect(node, isNotNull);
      expect(node!.hasFocus, isTrue);
    });
  });

  group('Library toolbar search dropdown', () {
    Future<ProviderContainer> pumpToolbar(
      WidgetTester tester, {
      List<Fragment$MangaDto> library = const [],
    }) async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          loggedInTrackersProvider.overrideWithValue(
            const AsyncData(<Fragment$TrackerDto>[]),
          ),
          libraryTagListProvider.overrideWithValue(const AsyncData(<String>[])),
          libraryMangaListProvider.overrideWith((ref) async => library),
          visibleCategoryListProvider.overrideWithValue(
            const AsyncData(<Fragment$CategoryDto>[]),
          ),
          ...unreachableServerStubs,
        ],
      );
      addTearDown(container.dispose);
      _setSize(tester, _desktop);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: DesktopLibraryToolbar()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    group('History desktop header', () {
      HistoryItemDto historyItem({
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

      final items = [
        historyItem(id: 1, series: 'Sword Chronicles', chapter: 'Chapter 12'),
        historyItem(id: 2, series: 'Other Manga', chapter: 'Chapter 1'),
      ];

      Future<ProviderContainer> pumpHistory(
        WidgetTester tester, {
        Size size = _desktop,
        bool withRouter = true,
      }) async {
        SharedPreferences.setMockInitialValues({});
        final sp = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sp),
            readingHistoryProvider.overrideWith(
              () => _FakeReadingHistory(items),
            ),
            historyGroupedByDateProvider.overrideWith(
              (ref) => [HistoryGroup(title: 'Today', items: items)],
            ),
            libraryMangaListProvider.overrideWith((ref) async => null),
            visibleCategoryListProvider.overrideWithValue(
              const AsyncData(<Fragment$CategoryDto>[]),
            ),
            ...unreachableServerStubs,
          ],
        );
        addTearDown(container.dispose);
        _setSize(tester, size);
        Widget home() => const Scaffold(body: HistoryScreen());
        if (withRouter) {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp.router(
                routerConfig: GoRouter(
                  initialLocation: '/history',
                  routes: [
                    GoRoute(path: '/history', builder: (_, _) => home()),
                    GoRoute(
                      path: '/updates',
                      builder: (_, _) => const Scaffold(
                        body: Center(child: Text('UPDATES PAGE')),
                      ),
                    ),
                    GoRoute(
                      path: '/manga/:mangaId',
                      builder: (_, _) => const Scaffold(
                        body: Center(child: Text('MANGA PAGE')),
                      ),
                    ),
                    GoRoute(
                      path: '/global-search',
                      builder: (_, _) => const Scaffold(
                        body: Center(child: Text('GLOBAL SEARCH PAGE')),
                      ),
                    ),
                    GoRoute(
                      path: '/library/:categoryId',
                      builder: (_, _) => const Scaffold(
                        body: Center(child: Text('LIBRARY PAGE')),
                      ),
                    ),
                  ],
                ),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
              ),
            ),
          );
        } else {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: home(),
              ),
            ),
          );
        }
        await tester.pumpAndSettle();
        return container;
      }

      Finder headerField() => find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(DesktopSearchField),
      );

      Finder headerTextField() =>
          find.descendant(of: headerField(), matching: find.byType(TextField));

      testWidgets('header field replaces the title; no second box', (
        tester,
      ) async {
        await pumpHistory(tester);
        expect(tester.takeException(), isNull);

        expect(headerField(), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('History'),
          ),
          findsNothing,
          reason: 'the sidebar already names the page',
        );
        // One search box, not two: no inline "Search history..." bar.
        expect(find.byType(SearchField), findsNothing);
      });

      testWidgets('typing filters the list and shows History first', (
        tester,
      ) async {
        await pumpHistory(tester);

        await tester.enterText(headerTextField(), 'sw');
        await tester.pump();

        // The list below filters live.
        expect(find.text('Chapter 12'), findsWidgets);
        expect(find.text('Chapter 1'), findsNothing);
        // The dropdown leads with its History section, then unified rows.
        expect(find.text('History'), findsOneWidget);
        expect(find.text('Search all sources for "sw"'), findsOneWidget);
      });

      testWidgets('Esc closes; Esc again clears', (tester) async {
        final container = await pumpHistory(tester);

        await tester.enterText(headerTextField(), 'sw');
        await tester.pump();
        expect(find.text('Search all sources for "sw"'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.text('Search all sources for "sw"'), findsNothing);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(container.read(historySearchQueryProvider), isEmpty);
      });

      testWidgets('opening a series from History clears the query', (
        tester,
      ) async {
        final container = await pumpHistory(tester);

        await tester.enterText(headerTextField(), 'sw');
        await tester.pump();
        // The dropdown History row (cover + chapter subtitle); scoped to the
        // anchored panel, since the filtered list below shows the same chapter.
        final row = find.descendant(
          of: find.byType(CompositedTransformFollower),
          matching: find.text('Chapter 12'),
        );
        expect(row, findsOneWidget);
        await tester.tap(row);
        await tester.pumpAndSettle();

        expect(find.text('MANGA PAGE'), findsOneWidget);
        expect(container.read(historySearchQueryProvider), isEmpty);
      });

      testWidgets('phone keeps the title and gets the search entry', (
        tester,
      ) async {
        await pumpHistory(
          tester,
          size: const Size(412, 900),
          withRouter: false,
        );
        expect(tester.takeException(), isNull);

        expect(find.byType(DesktopSearchField), findsNothing);
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('History'),
          ),
          findsOneWidget,
        );
        // Slice 4b: phone searches from the app-bar entry, which applies to
        // the filter on submit — no live inline field anymore.
        expect(find.byType(SearchField), findsNothing);
        expect(find.byType(PhoneSearchEntry), findsOneWidget);
      });
    });

    testWidgets('shows Go to + Search all sources, no Library section', (
      tester,
    ) async {
      final container = await pumpToolbar(
        tester,
        library: [_manga(1, 'Updated Sword')],
      );

      await tester.enterText(find.byType(TextField), 'upd');
      await tester.pump();

      expect(
        container.read(libraryQueryProvider),
        'upd',
        reason: 'live filtering still writes the library query',
      );
      expect(find.text('Go to'), findsOneWidget);
      expect(find.text('Updates'), findsOneWidget);
      // The Settings section grew (Server/Tracking rows also match "upd"),
      // so the trailing row can sit below the fold: look offstage too.
      expect(
        find.text('Search all sources for "upd"', skipOffstage: false),
        findsOneWidget,
        reason: 'always offered while text is non-empty',
      );
      expect(
        find.text('Library'),
        findsNothing,
        reason: 'the grid below is already the filtered library',
      );
    });
  });

  group('Desktop search follow-ups', () {
    Future<ProviderContainer> pumpHost(
      WidgetTester tester,
      Widget child, {
      List<Fragment$MangaDto> library = const [],
    }) async {
      _setSize(tester, _desktop);
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          quickSearchToggleProvider.overrideWith(_ToggleOn.new),
          libraryMangaListProvider.overrideWith((ref) async => library),
          visibleCategoryListProvider.overrideWithValue(_emptyCategories),
          ...unreachableServerStubs,
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: GlobalShortcutHost(child: child),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    Widget hostApp(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(child: SizedBox(width: 500, child: child)),
      ),
    );

    // A hidden keep-alive shell branch, like go_router renders inactive
    // branches: offstage with tickers disabled.
    Widget inactiveBranch(Widget child) => TickerMode(
      enabled: false,
      child: Offstage(offstage: true, child: child),
    );

    Future<void> sendCtrlF(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets('blur keeps the field registered; dispose unregisters', (
      tester,
    ) async {
      final container = await _pumpField(tester);

      // Registered on mount.
      await tester.pump();
      final node = container.read(desktopSearchFocusNodeProvider);
      expect(node, isNotNull);

      // Clicking elsewhere blurs the field but must not unregister it.
      await tester.tap(_fieldTextField());
      await tester.pump();
      expect(node!.hasFocus, isTrue);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(node.hasFocus, isFalse);
      expect(
        container.read(desktopSearchFocusNodeProvider),
        same(node),
        reason: 'Ctrl+F must still find the field after a blur',
      );

      // Unmounting the field releases the registration.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(container.read(desktopSearchFocusNodeProvider), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ctrl+F focuses the visible field with two mounted', (
      tester,
    ) async {
      final container = await pumpHost(
        tester,
        hostApp(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Inactive branch, kept alive but hidden; registers first.
              inactiveBranch(_boundField()),
              _boundField(),
            ],
          ),
        ),
      );

      await sendCtrlF(tester);

      expect(container.read(quickOpenVisibleProvider), isFalse);
      final node = container.read(desktopSearchFocusNodeProvider);
      expect(node, isNotNull);
      expect(node!.hasFocus, isTrue);
      expect(TickerMode.valuesOf(node.context!).enabled, isTrue);
    });

    testWidgets('Ctrl+F with only a hidden field opens the overlay', (
      tester,
    ) async {
      final container = await pumpHost(
        tester,
        hostApp(inactiveBranch(_boundField())),
      );

      // The hidden field is the only registrant; it must not take focus.
      expect(container.read(desktopSearchFocusNodeProvider), isNotNull);

      await sendCtrlF(tester);

      expect(
        container.read(quickOpenVisibleProvider),
        isTrue,
        reason: 'no current field, so the overlay opens',
      );
      expect(container.read(desktopSearchFocusNodeProvider)!.hasFocus, isFalse);
    });

    testWidgets('operator-only query still opens the Filters dropdown', (
      tester,
    ) async {
      await _pumpField(tester);

      await tester.enterText(_fieldTextField(), 'unread:');
      await tester.pump();
      await tester.pump();

      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('unread:true'), findsOneWidget);
    });

    testWidgets('History Enter opens the top History result first', (
      tester,
    ) async {
      final historyItem = Fragment$HistoryChapterDto(
        id: 1,
        chapterNumber: 1,
        fetchedAt: '0',
        isBookmarked: false,
        isDownloaded: false,
        isRead: false,
        lastPageRead: 4,
        lastReadAt: '1700000000',
        mangaId: 1,
        name: 'Chapter 12',
        pageCount: 10,
        sourceOrder: 1,
        uploadDate: '0',
        url: '/c/1',
        meta: const [],
        manga: Fragment$HistoryChapterDto$manga(
          id: 1,
          inLibrary: true,
          title: 'Sword Chronicles',
          unreadCount: 3,
        ),
      );
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          readingHistoryProvider.overrideWith(
            () => _FakeReadingHistory([historyItem]),
          ),
          historyGroupedByDateProvider.overrideWith(
            (ref) => [
              HistoryGroup(title: 'Today', items: [historyItem]),
            ],
          ),
          libraryMangaListProvider.overrideWith((ref) async => null),
          visibleCategoryListProvider.overrideWithValue(_emptyCategories),
          ...unreachableServerStubs,
        ],
      );
      addTearDown(container.dispose);
      _setSize(tester, _desktop);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/history',
              routes: [
                GoRoute(
                  path: '/history',
                  builder: (_, _) => const Scaffold(body: HistoryScreen()),
                ),
                GoRoute(
                  path: '/manga/:mangaId',
                  builder: (_, _) =>
                      const Scaffold(body: Center(child: Text('MANGA PAGE'))),
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

      final headerField = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(TextField),
      );
      await tester.enterText(headerField, 'sw');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        find.text('MANGA PAGE'),
        findsOneWidget,
        reason: 'Enter opens the top History result before the unified one',
      );
      expect(container.read(historySearchQueryProvider), isEmpty);
    });

    testWidgets('Esc on an empty closed field propagates to go back', (
      tester,
    ) async {
      _setSize(tester, _desktop);
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          libraryMangaListProvider.overrideWith((ref) async => null),
          visibleCategoryListProvider.overrideWithValue(_emptyCategories),
          ...unreachableServerStubs,
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('HOME'))),
          ),
          // The host wraps the page below the router, like the app shell.
          GoRoute(
            path: '/two',
            builder: (_, _) => GlobalShortcutHost(
              child: Scaffold(
                body: Center(child: SizedBox(width: 500, child: _boundField())),
              ),
            ),
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

      router.push('/two');
      await tester.pumpAndSettle();
      await tester.tap(_fieldTextField());
      await tester.pump();
      expect(container.read(unifiedSearchQueryProvider), isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(
        find.text('HOME'),
        findsOneWidget,
        reason: 'empty closed field lets Esc reach the global back handler',
      );
      expect(tester.takeException(), isNull);
    });

    test('per-query library results dispose when unlistened', () async {
      final container = ProviderContainer(
        overrides: [
          libraryMangaListProvider.overrideWith(
            (ref) async => [_manga(1, 'Sword Chronicles')],
          ),
          visibleCategoryListProvider.overrideWithValue(_emptyCategories),
        ],
      );
      addTearDown(container.dispose);

      await container.read(libraryMangaListProvider.future);
      final target = unifiedLibraryResultsForProvider('sw');
      final first = container.read(target);
      expect(first.map((m) => m.title), contains('Sword Chronicles'));

      await container.pump();
      final second = container.read(target);

      expect(
        identical(first, second),
        isFalse,
        reason: 'stale per-query results must not stay alive',
      );
    });
  });
}
