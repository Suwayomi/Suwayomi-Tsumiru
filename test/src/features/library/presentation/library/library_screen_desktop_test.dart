// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/data/default_category.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/library/presentation/library/library_screen.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/desktop_library_toolbar.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/data/syncyomi_settings_provider.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/sorayomi.dart';
import 'package:tsumiru/src/utils/theme/app_theme_builder.dart';

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
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        scrollBehavior: const AppScrollBehavior(),
        home: ScrollbarTheme(
          data: scrollbarTheme ?? const ScrollbarThemeData(),
          child: const LibraryScreen(categoryId: 1),
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
      await _pumpLibrary(tester, surface: const Size(800, 600));

      expect(tester.takeException(), isNull);
      expect(find.byType(DesktopLibraryToolbar), findsNothing);
      expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
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

    testWidgets('tablet sticky search keeps scrollbars off, no clash', (
      tester,
    ) async {
      await _pumpLibrary(
        tester,
        surface: const Size(900, 900),
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

    testWidgets('tablet toggled search enables global search with a query', (
      tester,
    ) async {
      final container = await _pumpLibrary(
        tester,
        surface: const Size(900, 980),
      );

      // Open the toggled search field: no query yet, so the button is
      // present but disabled — the tablet-only way into Global Search.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search_rounded));
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
    });

    testWidgets('tablet sticky search shows global search with a query', (
      tester,
    ) async {
      final container = await _pumpLibrary(
        tester,
        surface: const Size(900, 980),
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
}
