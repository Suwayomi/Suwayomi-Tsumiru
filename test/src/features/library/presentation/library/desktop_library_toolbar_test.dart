// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/desktop_library_toolbar.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/library_manga_organizer.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../../../../../helpers/unreachable_server_stubs.dart';

Future<ProviderContainer> _pumpToolbar(
  WidgetTester tester, {
  double width = 1400,
  double textScale = 1.0,
  List<Widget> trailing = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      // The sort control reads the logged-in trackers for the tracker-score
      // rule; never hit the network in widget tests.
      loggedInTrackersProvider.overrideWithValue(
        const AsyncData(<Fragment$TrackerDto>[]),
      ),
      libraryTagListProvider.overrideWithValue(const AsyncData(<String>[])),
      libraryMangaListProvider.overrideWith((ref) async => null),
      // The category summary reads this; never hit the network in widget tests.
      visibleCategoryListProvider.overrideWithValue(
        const AsyncData(<Fragment$CategoryDto>[]),
      ),
      ...unreachableServerStubs,
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = Size(width, 980);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(body: DesktopLibraryToolbar(trailing: trailing)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Taps the sort box label. Scoped to the [MenuAnchor] builder so the open
/// menu's duplicate label never matches.
Future<void> _tapSortBox(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: find.byType(MenuAnchor), matching: find.byType(Text)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('DesktopLibraryToolbar', () {
    testWidgets('typing updates libraryQueryProvider', (tester) async {
      final container = await _pumpToolbar(tester);

      await tester.enterText(find.byType(TextField), 'sword');
      await tester.pump();

      expect(container.read(libraryQueryProvider), 'sword');
      // The dropdown offers Search all sources; no separate button remains.
      expect(
        find.widgetWithIcon(IconButton, Icons.travel_explore_rounded),
        findsNothing,
      );
    });

    testWidgets('sort menu lists sorts; picking updates the provider', (
      tester,
    ) async {
      final container = await _pumpToolbar(tester);

      await _tapSortBox(tester);

      final expected = [
        for (final sort in librarySortDisplayOrder)
          if (sort != MangaSort.trackerScore) sort,
      ];
      expect(find.byType(MenuItemButton), findsNWidgets(expected.length));
      // Same order as the organizer: alphabetical first, random last, and
      // tracker score hidden without a logged-in tracker.
      final labels = tester
          .widgetList<MenuItemButton>(find.byType(MenuItemButton))
          .map((b) => (b.child! as Text).data!);
      expect(labels.toList(), [
        for (final sort in expected)
          switch (sort) {
            MangaSort.alphabetical => 'Alphabetical',
            MangaSort.rating => 'Rating',
            MangaSort.totalChapters => 'Total Chapters',
            MangaSort.lastRead => 'Last Read',
            MangaSort.lastUpdate => 'Last Update',
            MangaSort.unread => 'Unread',
            MangaSort.lastChapterDate => 'Latest Chapter',
            MangaSort.lastUpdated => 'Chapter Fetch Date',
            MangaSort.dateAdded => 'Date Added',
            MangaSort.trackerScore => 'Tracker score',
            MangaSort.random => 'Random',
          },
      ]);
      expect(find.text('Tracker score'), findsNothing);

      await tester.tap(find.widgetWithText(MenuItemButton, 'Alphabetical'));
      await tester.pumpAndSettle();
      expect(container.read(libraryMangaSortProvider), MangaSort.alphabetical);
    });

    testWidgets('filter opens an anchored panel, not a drawer', (tester) async {
      await _pumpToolbar(tester);

      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);
    });

    testWidgets('compact mode at 520 hides labels but keeps every action', (
      tester,
    ) async {
      final container = await _pumpToolbar(tester, width: 520);

      expect(tester.takeException(), isNull);
      expect(find.text('Last Read'), findsNothing);
      expect(find.text('Filter'), findsNothing);
      expect(find.byTooltip('Last Read'), findsOneWidget);
      expect(find.byTooltip('Filter'), findsOneWidget);

      // The direction button still toggles.
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.arrow_downward_rounded),
      );
      await tester.pump();
      expect(container.read(libraryMangaSortDirectionProvider), isTrue);

      // The sort trigger still opens the menu and picking still applies.
      await tester.tap(find.byTooltip('Last Read'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(MenuItemButton, 'Alphabetical'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(MenuItemButton, 'Alphabetical'));
      await tester.pumpAndSettle();
      expect(container.read(libraryMangaSortProvider), MangaSort.alphabetical);

      // The filter icon still opens the panel.
      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();
      expect(find.text('Downloaded'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
