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
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/desktop_search_field.dart';
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
    testWidgets('shows search, sort, filter, display; no Library title', (
      tester,
    ) async {
      await _pumpToolbar(tester);

      expect(tester.takeException(), isNull);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.hintText, 'Search title or author...');
      expect(find.text('Last Read'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is DesktopToolbarBox && w.width == 230),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is DesktopToolbarBox && (w.width == 180 || w.width == 40),
        ),
        findsNothing,
      );
      expect(find.text('Filter'), findsOneWidget);
      expect(find.byTooltip('Display'), findsOneWidget);
      expect(find.text('Library'), findsNothing);
    });

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
            (w) => w is DesktopToolbarBox && w.width == 230,
          ),
          matching: find.widgetWithIcon(
            IconButton,
            Icons.arrow_downward_rounded,
          ),
        ),
      );
      expect(direction.onPressed, isNull);

      final seed = container.read(librarySortRandomSeedProvider) ?? 0;
      await _tapSortBox(tester);
      await tester.tap(find.widgetWithText(MenuItemButton, 'Random'));
      await tester.pumpAndSettle();
      expect(container.read(librarySortRandomSeedProvider), seed + 1);
    });

    testWidgets('search tips show three paragraphs and two code chips', (
      tester,
    ) async {
      await _pumpToolbar(tester);

      await tester.tap(find.byTooltip('Search tips'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Search tips'), findsOneWidget);
      expect(
        find.text('Plain words match the title, author, genres and tags.'),
        findsOneWidget,
      );
      expect(find.text('author:oda'), findsOneWidget);
      expect(find.text('-tag:dropped'), findsOneWidget);
      expect(find.textContaining('Match any of these'), findsNothing);
      // Each example appears only inside its chip: the plain text spans
      // around the chips must not repeat them.
      String plainOf(InlineSpan span) {
        if (span is! TextSpan) return '';
        final buffer = StringBuffer(span.text ?? '');
        for (final child in span.children ?? const <InlineSpan>[]) {
          buffer.write(plainOf(child));
        }
        return buffer.toString();
      }

      // Only the tip paragraphs use Text.rich (plain + chip + plain
      // spans); the chips themselves are plain Text widgets and are
      // covered by the findsOneWidget checks above.
      final plains = tester
          .widgetList<RichText>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(RichText),
            ),
          )
          .where(
            (rich) =>
                rich.text is TextSpan &&
                (rich.text as TextSpan).children?.isNotEmpty == true,
          )
          .map((rich) => plainOf(rich.text))
          .toList();
      expect(plains, isNotEmpty);
      for (final plain in plains) {
        expect(plain, isNot(contains('author:oda')));
        expect(plain, isNot(contains('-tag:dropped')));
      }
      expect(
        plains.any(
          (plain) => plain.contains('Type a field and a colon, like '),
        ),
        isTrue,
      );
      expect(
        plains.any(
          (plain) => plain.contains(
            ', to search one field. Suggestions show as you type.',
          ),
        ),
        isTrue,
      );
      expect(
        plains.any((plain) => plain.contains('Exclude with a minus: ')),
        isTrue,
      );
    });

    testWidgets('filter opens an anchored panel, not a drawer', (tester) async {
      await _pumpToolbar(tester);

      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);
    });

    testWidgets('display opens the display panel', (tester) async {
      await _pumpToolbar(tester);

      await tester.tap(find.byTooltip('Display'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Display Mode'), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);
    });

    testWidgets('full mode at 1100 keeps the sort label and Filter text', (
      tester,
    ) async {
      await _pumpToolbar(tester, width: 1100);

      expect(tester.takeException(), isNull);
      expect(find.text('Last Read'), findsOneWidget);
      expect(find.text('Filter'), findsOneWidget);
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

    testWidgets('compact mode at 360 reports no overflow', (tester) async {
      await _pumpToolbar(tester, width: 360);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(DesktopLibraryToolbar), findsOneWidget);
      expect(find.text('Filter'), findsNothing);
      expect(find.byTooltip('Filter'), findsOneWidget);
    });

    testWidgets('full mode at 900 with default text scale', (tester) async {
      await _pumpToolbar(tester, width: 900);

      expect(tester.takeException(), isNull);
      expect(find.text('Last Read'), findsOneWidget);
      expect(find.text('Filter'), findsOneWidget);
    });

    testWidgets('text scale 1.5 at 900 switches to compact', (tester) async {
      await _pumpToolbar(tester, width: 900, textScale: 1.5);

      expect(tester.takeException(), isNull);
      expect(find.text('Last Read'), findsNothing);
      expect(find.text('Filter'), findsNothing);
      expect(find.byTooltip('Last Read'), findsOneWidget);
      expect(find.byTooltip('Filter'), findsOneWidget);
    });

    testWidgets('compact trailing actions stay visible and tappable', (
      tester,
    ) async {
      var syncTaps = 0;
      var menuTaps = 0;
      await _pumpToolbar(
        tester,
        width: 520,
        // SizedBox pins the production 48 px IconButton/PopupMenuButton
        // widths deterministically (a bare M3 IconButton sizes itself 40).
        trailing: [
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: const Icon(Icons.cloud_sync_rounded),
              tooltip: 'Sync now',
              onPressed: () => syncTaps++,
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: PopupMenuButton<int>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'Updates',
              itemBuilder: (context) => [
                PopupMenuItem<int>(
                  value: 1,
                  onTap: () => menuTaps++,
                  child: const Text('Global update'),
                ),
              ],
            ),
          ),
        ],
      );
      expect(tester.takeException(), isNull);

      // Both trailing buttons are 48 px wide and fully inside the toolbar.
      final toolbarRect = tester.getRect(find.byType(DesktopLibraryToolbar));
      final syncRect = tester.getRect(find.byTooltip('Sync now'));
      final menuRect = tester.getRect(find.byTooltip('Updates'));
      expect(syncRect.width, 48.0);
      expect(menuRect.width, 48.0);
      for (final rect in [syncRect, menuRect]) {
        expect(rect.left, greaterThanOrEqualTo(toolbarRect.left));
        expect(rect.right, lessThanOrEqualTo(toolbarRect.right));
      }

      await tester.tap(find.byTooltip('Sync now'));
      await tester.pump();
      expect(syncTaps, 1);

      await tester.tap(find.byTooltip('Updates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Global update'));
      await tester.pump();
      expect(menuTaps, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('search field keeps element, text and focus across resize', (
      tester,
    ) async {
      final container = await _pumpToolbar(tester, width: 1100);
      expect(find.text('Last Read'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'sword');
      await tester.pump();
      expect(container.read(libraryQueryProvider), 'sword');

      final before = tester.element(find.byType(DesktopSearchField));
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        isTrue,
      );

      tester.view.physicalSize = const Size(520, 980);
      await tester.pumpAndSettle();

      expect(find.text('Last Read'), findsNothing);
      final after = tester.element(find.byType(DesktopSearchField));
      expect(identical(after, before), isTrue);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'sword',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow toolbar with three trailing buttons has no overflow', (
      tester,
    ) async {
      await _pumpToolbar(
        tester,
        width: 360,
        // 48 px trailing, the worst case from the clipped-actions report.
        trailing: [
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: const Icon(Icons.swap_horiz_rounded),
              tooltip: 'Migrate',
              onPressed: () {},
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: const Icon(Icons.cloud_sync_rounded),
              tooltip: 'Sync now',
              onPressed: () {},
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: PopupMenuButton<int>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'Updates',
              itemBuilder: (context) => [
                const PopupMenuItem<int>(
                  value: 1,
                  child: Text('Global update'),
                ),
              ],
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
