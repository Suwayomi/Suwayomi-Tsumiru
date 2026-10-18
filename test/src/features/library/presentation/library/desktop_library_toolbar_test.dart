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
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/desktop_library_toolbar.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/library_manga_organizer.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

Future<ProviderContainer> _pumpToolbar(
  WidgetTester tester, {
  void Function()? onOpenOrganizer,
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
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(1400, 980);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DesktopLibraryToolbar(
            onOpenOrganizer: onOpenOrganizer ?? () {},
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
    testWidgets('shows search, sort, filter, display; no Library title', (
      tester,
    ) async {
      await _pumpToolbar(tester);

      expect(tester.takeException(), isNull);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.hintText, 'Search title, author, source...');
      expect(find.text('Last Read'), findsOneWidget);
      expect(find.text('Filter'), findsOneWidget);
      expect(find.byTooltip('Display'), findsOneWidget);
      expect(find.text('Library'), findsNothing);
    });

    testWidgets('typing updates libraryQueryProvider', (tester) async {
      final container = await _pumpToolbar(tester);

      await tester.enterText(find.byType(TextField), 'sword');
      await tester.pump();

      expect(container.read(libraryQueryProvider), 'sword');
      // Search-all-sources is only enabled with a query.
      final global = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.travel_explore_rounded),
      );
      expect(global.onPressed, isNotNull);
    });

    testWidgets('sort menu lists sorts; picking updates the provider', (
      tester,
    ) async {
      final container = await _pumpToolbar(tester);

      // No query: search-all-sources stays disabled.
      final global = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.travel_explore_rounded),
      );
      expect(global.onPressed, isNull);

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

    testWidgets('direction button toggles the provider', (tester) async {
      final container = await _pumpToolbar(tester);

      expect(container.read(libraryMangaSortDirectionProvider), isNot(true));
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.arrow_downward_rounded),
      );
      await tester.pump();
      expect(container.read(libraryMangaSortDirectionProvider), isTrue);
      expect(
        find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
        findsOneWidget,
      );
    });

    testWidgets('random disables direction; re-picking reseeds', (
      tester,
    ) async {
      final container = await _pumpToolbar(tester);

      await _tapSortBox(tester);
      await tester.tap(find.widgetWithText(MenuItemButton, 'Random'));
      await tester.pumpAndSettle();
      expect(container.read(libraryMangaSortProvider), MangaSort.random);

      // Direction is meaningless for random: disabled, layout unchanged.
      final direction = tester.widget<IconButton>(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is DesktopToolbarBox && w.width == 40,
          ),
          matching: find.byType(IconButton),
        ),
      );
      expect(direction.onPressed, isNull);

      final seed = container.read(librarySortRandomSeedProvider) ?? 0;
      await _tapSortBox(tester);
      await tester.tap(find.widgetWithText(MenuItemButton, 'Random'));
      await tester.pumpAndSettle();
      expect(container.read(librarySortRandomSeedProvider), seed + 1);
    });

    testWidgets('filter and display open the organizer', (tester) async {
      var opened = 0;
      await _pumpToolbar(tester, onOpenOrganizer: () => opened++);

      await tester.tap(find.text('Filter'));
      await tester.pump();
      await tester.tap(find.byTooltip('Display'));
      await tester.pump();
      expect(opened, 2);
    });
  });
}
