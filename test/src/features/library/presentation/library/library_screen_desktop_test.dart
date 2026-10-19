// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/data/default_category.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/library/presentation/library/library_screen.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/desktop_library_panels.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/desktop_library_toolbar.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/desktop_search_field.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/data/syncyomi_settings_provider.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/sorayomi.dart';
import 'package:tsumiru/src/utils/theme/app_theme_builder.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';

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

/// Pumps the real [LibraryScreen] with two empty categories. Phone widths
/// take the legacy app bar; desktop widths take the toolbar + tab strip.
Future<ProviderContainer> _pumpLibrary(
  WidgetTester tester, {
  required Size surface,
  bool withManga = false,
  bool persistentSearchBar = false,
  ScrollbarThemeData? scrollbarTheme,
}) async {
  SharedPreferences.setMockInitialValues({
    if (persistentSearchBar) 'libraryPersistentSearchBar': true,
  });
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      // Never hit the network in widget tests.
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
      categoryMangaListProvider.overrideWith(
        (ref, categoryId) async => <Fragment$MangaDto>[],
      ),
      // The sticky search bar gates on the whole-library list being loaded.
      libraryMangaListProvider.overrideWith(
        (ref) async => <Fragment$MangaDto>[],
      ),
      categoryMangaListWithQueryAndFilterProvider(
        categoryId: 1,
      ).overrideWithValue(
        AsyncData([
          for (var i = 1; i <= 30; i++)
            if (withManga) _manga(i, 'Alpha $i'),
        ]),
      ),
      categoryMangaListWithQueryAndFilterProvider(
        categoryId: 2,
      ).overrideWithValue(
        AsyncData([
          for (var i = 1; i <= 30; i++)
            if (withManga) _manga(100 + i, 'Beta $i'),
        ]),
      ),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = surface;
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
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        scrollBehavior: const AppScrollBehavior(),
        home: ScrollbarTheme(
          data: scrollbarTheme ?? const ScrollbarThemeData(),
          // Native desktop draws the toolbar in the shell bar above the
          // page; narrower surfaces keep the page on its own.
          child: Builder(
            builder: (context) => showsMergedTopBar(context)
                ? const Scaffold(
                    body: Column(
                      children: [
                        DesktopTopBar(),
                        Expanded(child: LibraryScreen(categoryId: 1)),
                      ],
                    ),
                  )
                : const LibraryScreen(categoryId: 1),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('LibraryScreen desktop header', () {
    testWidgets('desktop shows the toolbar, no Library title', (tester) async {
      await _pumpLibrary(tester, surface: const Size(1400, 980));

      expect(tester.takeException(), isNull);
      expect(find.byType(DesktopLibraryToolbar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Library'), findsNothing);
      // Both categories fit: the strip shows them, no More control.
      expect(find.text('One', findRichText: true), findsOneWidget);
      expect(find.text('Two', findRichText: true), findsOneWidget);
      expect(find.textContaining('More (', findRichText: true), findsNothing);
    });

    testWidgets('phone keeps the old AppBar (no regression)', (tester) async {
      await _pumpLibrary(tester, surface: const Size(412, 800));

      expect(tester.takeException(), isNull);
      expect(find.byType(DesktopLibraryToolbar), findsNothing);
      expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
    });

    testWidgets('900x900 shows the desktop toolbar, no AppBar', (tester) async {
      await _pumpLibrary(tester, surface: const Size(900, 900));

      expect(tester.takeException(), isNull);
      expect(find.byType(DesktopLibraryToolbar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Library'), findsNothing);
    });

    testWidgets('landscape phone keeps the tablet layout', (tester) async {
      final container = await _pumpLibrary(
        tester,
        surface: const Size(915, 412),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(DesktopLibraryToolbar), findsNothing);
      expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);

      // The in-between layout keeps the tablet-only Global Search button.
      container.read(libraryQueryProvider.notifier).update('sword');
      await tester.pumpAndSettle();
      expect(
        find.widgetWithIcon(IconButton, Icons.travel_explore_rounded),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('two tabs scroll with a themed scrollbar, no clash', (
      tester,
    ) async {
      await _pumpLibrary(
        tester,
        surface: const Size(1400, 980),
        withManga: true,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Alpha 1'), findsOneWidget);

      // Scroll the first tab, then switch: both tabs are alive during the
      // switch animation, and sharing one controller threw "attached to more
      // than one ScrollPosition" when the second tab attached.
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Two', findRichText: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Beta 1'), findsOneWidget);

      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollbar), findsWidgets);
    });

    testWidgets('landscape-phone sticky search keeps scrollbars off, no clash', (
      tester,
    ) async {
      await _pumpLibrary(
        tester,
        surface: const Size(915, 412),
        withManga: true,
        persistentSearchBar: true,
        scrollbarTheme: wideScreenScrollbarTheme(const ColorScheme.light()),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Alpha 1'), findsOneWidget);

      // Below desktop the tabs share the NestedScrollView controller, so the
      // always-visible wide-screen scrollbar would throw "attached to more
      // than one ScrollPosition" on switch — scrollbars stay off instead.
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Two', findRichText: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Beta 1'), findsOneWidget);

      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'landscape-phone toggled search enables global search with a query',
      (tester) async {
        final container = await _pumpLibrary(
          tester,
          surface: const Size(915, 412),
        );

        // Open the toggled search field: no query yet, so the button is
        // present but disabled — the in-between layout's way into Global
        // Search.
        await tester.tap(
          find.widgetWithIcon(IconButton, Icons.search_rounded),
        );
        await tester.pumpAndSettle();
        var global = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.travel_explore_rounded),
        );
        expect(global.onPressed, isNull);

        container.read(libraryQueryProvider.notifier).update('sword');
        await tester.pumpAndSettle();
        global = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.travel_explore_rounded),
        );
        expect(global.onPressed, isNotNull);
      },
    );

    testWidgets('landscape-phone sticky search shows global search with a query', (
      tester,
    ) async {
      final container = await _pumpLibrary(
        tester,
        surface: const Size(915, 412),
        persistentSearchBar: true,
      );

      container.read(libraryQueryProvider.notifier).update('sword');
      await tester.pumpAndSettle();

      expect(
        find.widgetWithIcon(IconButton, Icons.travel_explore_rounded),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone shows no global search button', (tester) async {
      final container = await _pumpLibrary(
        tester,
        surface: const Size(412, 800),
      );
      container.read(libraryQueryProvider.notifier).update('sword');
      await tester.pumpAndSettle();
      expect(
        find.widgetWithIcon(IconButton, Icons.travel_explore_rounded),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('desktop shows no global search button', (tester) async {
      final container = await _pumpLibrary(
        tester,
        surface: const Size(1400, 980),
      );
      container.read(libraryQueryProvider.notifier).update('sword');
      await tester.pumpAndSettle();
      expect(
        find.widgetWithIcon(IconButton, Icons.travel_explore_rounded),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Library toolbar in the shell bar', () {
    bool insideBar(WidgetTester tester, Rect barRect, Finder control) {
      final rect = tester.getRect(control);
      return barRect.left <= rect.left &&
          rect.right <= barRect.right &&
          barRect.top <= rect.top &&
          rect.bottom <= barRect.bottom;
    }

    testWidgets('search, sort, filter and display sit inside the bar', (
      tester,
    ) async {
      await _pumpLibrary(tester, surface: const Size(1400, 980));

      expect(find.byType(DesktopLibraryToolbar), findsOneWidget);
      final barRect = tester.getRect(find.byType(DesktopTopBar));
      expect(
        insideBar(tester, barRect, find.byType(DesktopLibraryToolbar)),
        isTrue,
      );
      expect(
        insideBar(tester, barRect, find.byType(DesktopSearchField)),
        isTrue,
        reason: 'search field',
      );
      expect(
        insideBar(tester, barRect, find.byIcon(Icons.sort_rounded)),
        isTrue,
        reason: 'sort control',
      );
      expect(
        insideBar(tester, barRect, find.text('Filter')),
        isTrue,
        reason: 'filter control',
      );
      expect(
        insideBar(tester, barRect, find.byTooltip('Display')),
        isTrue,
        reason: 'display control',
      );

      // Category tabs stay in the page body under the bar.
      final tabTop = tester
          .getTopLeft(find.text('One', findRichText: true))
          .dy;
      expect(tabTop, greaterThan(barRect.bottom - 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('filter panel opens under the filter button', (tester) async {
      await _pumpLibrary(tester, surface: const Size(1400, 980));

      final buttonBox = find.ancestor(
        of: find.descendant(
          of: find.byType(DesktopLibraryToolbar),
          matching: find.text('Filter'),
        ),
        matching: find.byType(DesktopToolbarBox),
      );
      expect(buttonBox, findsOneWidget);
      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();

      expect(find.byType(DesktopLibraryFilterPanel), findsOneWidget);
      final buttonRect = tester.getRect(buttonBox);
      final panelRect = tester.getRect(find.byType(DesktopLibraryFilterPanel));
      expect(
        panelRect.top,
        greaterThanOrEqualTo(buttonRect.bottom - 4),
        reason: 'the panel opens under its button, not over it',
      );
      expect(panelRect.left, lessThan(buttonRect.right));
      expect(panelRect.right, greaterThan(buttonRect.left));
      expect(tester.takeException(), isNull);
    });
  });
}
