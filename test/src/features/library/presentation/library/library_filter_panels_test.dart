// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/library/data/default_category.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_grouping.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/library/presentation/library/library_screen.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/desktop_library_panels.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/desktop_library_toolbar.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/library_filter_segments.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/library_manga_organizer.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/data/syncyomi_settings_provider.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/manga_cover/providers/manga_cover_providers.dart';

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

Fragment$MangaDto$source _mangaSource() => Fragment$MangaDto$source(
  displayName: 'Test Source',
  iconUrl: '',
  id: '1',
  contentWarning: Enum$ContentWarning.SAFE,
  lang: 'en',
  name: 'Test Source',
  $extension: Fragment$MangaDto$source$extension(isObsolete: false),
);

Fragment$TrackerDto _tracker(int id, String name) => Fragment$TrackerDto(
  id: id,
  name: name,
  icon: '',
  isLoggedIn: true,
  isTokenExpired: false,
  supportsTrackDeletion: true,
  supportsPrivateTracking: false,
  supportsReadingDates: false,
  scores: const [],
  statuses: const [],
);

Fragment$MangaDto _manga(int id, List<String> genre) => Fragment$MangaDto(
  id: id,
  title: 'Manga $id',
  bookmarkCount: 0,
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  downloadCount: 0,
  genre: genre,
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: const [],
  source: _mangaSource(),
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  unreadCount: 0,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: 'https://example.com/manga/$id',
);

/// Pumps the real [LibraryScreen] with two empty categories and two tagged
/// manga (Action x2, Fantasy x1). Never hits the network.
///
/// On desktop widths the screen goes inside a replica of the desktop shell: a
/// 256 px sidebar (the extended rail width in `big_screen_navigation_bar.dart`)
/// plus a 40 px title strip, with the library in a nested [Navigator] like
/// go_router's branch Navigator. The nested Navigator owns its own Overlay
/// covering only the content area, which is what caught the window-global
/// anchor bug (panels pinned to the window's right edge instead of the
/// button's). Narrow surfaces pump the screen directly (phone, no shell).
Future<ProviderContainer> _createContainer({
  List<Fragment$TrackerDto> trackers = const <Fragment$TrackerDto>[],
}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      loggedInTrackersProvider.overrideWithValue(AsyncData(trackers)),
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
      categoryMangaListWithQueryAndFilterProvider(
        categoryId: 1,
      ).overrideWithValue(AsyncData<List<Fragment$MangaDto>?>(null)),
      categoryMangaListWithQueryAndFilterProvider(
        categoryId: 2,
      ).overrideWithValue(AsyncData<List<Fragment$MangaDto>?>(null)),
      libraryTagListProvider.overrideWithValue(
        const AsyncData(<String>['Action', 'Fantasy']),
      ),
      libraryMangaListProvider.overrideWith(
        (ref) async => [
          _manga(1, ['Action', 'Fantasy']),
          _manga(2, ['Action']),
        ],
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<ProviderContainer> _pumpLibrary(
  WidgetTester tester, {
  required Size surface,
  List<Fragment$TrackerDto> trackers = const <Fragment$TrackerDto>[],
}) async {
  final container = await _createContainer(trackers: trackers);
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  const library = LibraryScreen(categoryId: 1);
  final Widget home = surface.width >= 1200
      ? Scaffold(
          body: Row(
            children: [
              const SizedBox(width: 256),
              Expanded(
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    Expanded(
                      child: Navigator(
                        onGenerateRoute: (_) =>
                            MaterialPageRoute(builder: (_) => library),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        )
      : library;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _openFilterPanel(WidgetTester tester) async {
  await tester.tap(find.text('Filter'));
  await tester.pumpAndSettle();
}

Future<void> _openDisplayPanel(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Display'));
  await tester.pumpAndSettle();
}

/// Opens the Filter panel and returns the toolbar button rect plus the open
/// panel rect, both in screen coordinates.
Future<(Rect, Rect)> _openFilterAndMeasure(
  WidgetTester tester,
  Size surface,
) async {
  await _pumpLibrary(tester, surface: surface);
  await _openFilterPanel(tester);
  final buttonBox = find.ancestor(
    of: find.descendant(
      of: find.byType(DesktopLibraryToolbar),
      matching: find.text('Filter'),
    ),
    matching: find.byType(DesktopToolbarBox),
  );
  expect(buttonBox, findsOneWidget);
  return (
    tester.getRect(buttonBox),
    tester.getRect(find.byType(DesktopLibraryFilterPanel)),
  );
}

/// Opens the Display panel and returns the toolbar button rect plus the open
/// panel rect, both in screen coordinates.
Future<(Rect, Rect)> _openDisplayAndMeasure(
  WidgetTester tester,
  Size surface,
) async {
  await _pumpLibrary(tester, surface: surface);
  await _openDisplayPanel(tester);
  final buttonBox = find.ancestor(
    of: find.descendant(
      of: find.byType(DesktopLibraryToolbar),
      matching: find.byTooltip('Display'),
    ),
    matching: find.byType(DesktopToolbarBox),
  );
  expect(buttonBox, findsOneWidget);
  return (
    tester.getRect(buttonBox),
    tester.getRect(find.byType(DesktopLibraryDisplayPanel)),
  );
}

/// Pumps the real [DesktopLibraryFilterPanel] in its 720x600 box on the
/// given window surface. Used below 1200 px wide, where the library shows
/// the phone UI and the desktop panel cannot open from the toolbar.
Future<void> _pumpFilterBox(
  WidgetTester tester, {
  required Size surface,
  List<Fragment$TrackerDto> trackers = const <Fragment$TrackerDto>[],
}) async {
  final container = await _createContainer(trackers: trackers);
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 720,
              height: 600,
              child: DesktopLibraryFilterPanel(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<Fragment$TrackerDto> _fiveTrackers() => [
  _tracker(1, 'Tracker One'),
  _tracker(2, 'Tracker Two'),
  _tracker(3, 'Tracker Three'),
  _tracker(4, 'Tracker Four'),
  _tracker(5, 'Tracker Five'),
];

void main() {
  group('Library filter panel (desktop 1400x980)', () {
    testWidgets('filter opens an anchored panel; no drawer on desktop', (
      tester,
    ) async {
      await _pumpLibrary(tester, surface: const Size(1400, 980));

      expect(tester.takeException(), isNull);
      expect(find.byType(DesktopLibraryToolbar), findsOneWidget);

      await _openFilterPanel(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('Minimum rating'), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);
    });

    testWidgets('esc closes only the panel', (tester) async {
      await _pumpLibrary(tester, surface: const Size(1400, 980));
      await _openFilterPanel(tester);
      expect(find.text('Downloaded'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Downloaded'), findsNothing);
      expect(find.byType(DesktopLibraryToolbar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Yes/No segments write true/false on two filters', (
      tester,
    ) async {
      final container = await _pumpLibrary(
        tester,
        surface: const Size(1400, 980),
      );
      await _openFilterPanel(tester);

      // Row order: Downloaded, Storage, Read Status, Started, ...
      await tester.tap(find.text('Yes').at(0));
      await tester.pump();
      expect(container.read(libraryMangaFilterDownloadedProvider), isTrue);

      await tester.tap(find.text('No').at(0));
      await tester.pump();
      expect(container.read(libraryMangaFilterDownloadedProvider), isFalse);

      await tester.tap(find.text('Yes').at(1));
      await tester.pump();
      expect(container.read(libraryMangaFilterStartedProvider), isTrue);

      await tester.tap(find.text('No').at(1));
      await tester.pump();
      expect(container.read(libraryMangaFilterStartedProvider), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reset is disabled when idle and clears every filter', (
      tester,
    ) async {
      final container = await _pumpLibrary(
        tester,
        surface: const Size(1400, 980),
      );
      await _openFilterPanel(tester);

      final reset = find.widgetWithText(TextButton, 'Reset');
      expect(tester.widget<TextButton>(reset).onPressed, isNull);

      container
          .read(libraryMangaFilterDownloadedProvider.notifier)
          .update(true);
      container.read(libraryMangaFilterMinRatingProvider.notifier).update(3);
      await tester.pump();

      expect(tester.widget<TextButton>(reset).onPressed, isNotNull);
      await tester.tap(reset);
      await tester.pump();

      expect(container.read(libraryMangaFilterDownloadedProvider), isNull);
      expect(container.read(libraryMangaFilterMinRatingProvider), 0);
      expect(tester.widget<TextButton>(reset).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('filter button shows the active count badge', (tester) async {
      final container = await _pumpLibrary(
        tester,
        surface: const Size(1400, 980),
      );

      container
          .read(libraryMangaFilterDownloadedProvider.notifier)
          .update(true);
      container.read(libraryMangaFilterLewdProvider.notifier).update(false);
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(DesktopLibraryToolbar),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('tags list shows counts; tapping a tag filters by it', (
      tester,
    ) async {
      final container = await _pumpLibrary(
        tester,
        surface: const Size(1400, 980),
      );
      await _openFilterPanel(tester);

      expect(find.text('All tags'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
      // Two series carry Action, one carries Fantasy.
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.text('Action'));
      await tester.pump();
      expect(
        container.read(libraryFilterTagsIncludeProvider),
        contains('Action'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('panel right edge sits under the Filter button (1400)', (
      tester,
    ) async {
      final (buttonRect, panelRect) = await _openFilterAndMeasure(
        tester,
        const Size(1400, 980),
      );
      expect(panelRect.width, 720);
      expect(panelRect.right - buttonRect.right, lessThanOrEqualTo(1.0));
      expect(panelRect.right - buttonRect.right, greaterThanOrEqualTo(-1.0));
      expect(
        panelRect.top,
        moreOrLessEquals(buttonRect.bottom + 6, epsilon: 1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('panel right edge sits under the Filter button (1920)', (
      tester,
    ) async {
      final (buttonRect, panelRect) = await _openFilterAndMeasure(
        tester,
        const Size(1920, 1080),
      );
      expect(panelRect.width, 720);
      expect(panelRect.right - buttonRect.right, lessThanOrEqualTo(1.0));
      expect(panelRect.right - buttonRect.right, greaterThanOrEqualTo(-1.0));
      expect(
        panelRect.top,
        moreOrLessEquals(buttonRect.bottom + 6, epsilon: 1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('panel stays inside the window (1200)', (tester) async {
      const surface = Size(1200, 800);
      final (_, panelRect) = await _openFilterAndMeasure(tester, surface);
      expect(panelRect.left, greaterThanOrEqualTo(7.0));
      expect(panelRect.right, lessThanOrEqualTo(surface.width - 7.0));
      expect(panelRect.top, greaterThanOrEqualTo(7.0));
      expect(panelRect.bottom, lessThanOrEqualTo(surface.height - 7.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('display panel right edge sits under the Display button', (
      tester,
    ) async {
      // The shell's nested Navigator overlay covers only the content area, so
      // a window-global anchor would pin this 820 px panel to the window's
      // right edge instead of the button's.
      final (buttonRect, panelRect) = await _openDisplayAndMeasure(
        tester,
        const Size(1400, 980),
      );
      expect(panelRect.width, 820);
      expect(panelRect.right - buttonRect.right, lessThanOrEqualTo(1.0));
      expect(panelRect.right - buttonRect.right, greaterThanOrEqualTo(-1.0));
      expect(
        panelRect.top,
        moreOrLessEquals(buttonRect.bottom + 6, epsilon: 1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('panel uses the series-page menu surface', (tester) async {
      await _pumpLibrary(tester, surface: const Size(1400, 980));
      await _openFilterPanel(tester);

      final panelBox = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 720 && w.height == 600,
      );
      expect(panelBox, findsOneWidget);
      final material = tester.widget<Material>(
        find.descendant(of: panelBox, matching: find.byType(Material)).first,
      );
      final scheme = Theme.of(
        tester.element(find.byType(DesktopLibraryFilterPanel)),
      ).colorScheme;
      expect(material.color, scheme.surfaceContainer);
      expect(material.elevation, 3);
      final shape = material.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(14));
      expect(shape.side.color, scheme.outlineVariant);
      expect(shape.side.width, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tag list fills the right column height', (tester) async {
      await _pumpLibrary(tester, surface: const Size(1400, 980));
      await _openFilterPanel(tester);

      final leftColumn = find.ancestor(
        of: find.text('Downloaded'),
        matching: find.byType(SingleChildScrollView),
      );
      expect(leftColumn, findsOneWidget);
      final tagList = find.ancestor(
        of: find.text('All tags'),
        matching: find.byType(ListView),
      );
      expect(tagList, findsOneWidget);
      final tagRect = tester.getRect(tagList);
      // Grown past the old ~3-row (150 px) cap ...
      expect(tagRect.height, greaterThan(150));
      // ... so its bottom aligns with the left column bottom.
      final leftRect = tester.getRect(leftColumn);
      expect(tagRect.bottom - leftRect.bottom, lessThanOrEqualTo(1.0));
      expect(tagRect.bottom - leftRect.bottom, greaterThanOrEqualTo(-1.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('five trackers fit without overflow (1400x980)', (
      tester,
    ) async {
      await _pumpLibrary(
        tester,
        surface: const Size(1400, 980),
        trackers: _fiveTrackers(),
      );
      await _openFilterPanel(tester);

      for (final name in [
        'Tracker One',
        'Tracker Two',
        'Tracker Three',
        'Tracker Four',
        'Tracker Five',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      final panel = find.byType(DesktopLibraryFilterPanel);
      expect(panel, findsOneWidget);
      // The right column scrolls as one (left keeps its own scroll view).
      expect(
        find.descendant(
          of: panel,
          matching: find.byType(SingleChildScrollView),
        ),
        findsNWidgets(2),
      );
      // The tag list shrank to its ~3-row minimum instead of overflowing ...
      final tagList = find.ancestor(
        of: find.text('All tags'),
        matching: find.byType(ListView),
      );
      expect(tagList, findsOneWidget);
      final tagRect = tester.getRect(tagList);
      expect(tagRect.height, lessThan(150), reason: 'tag list shrank first');
      expect(
        tagRect.height,
        greaterThan(70),
        reason: 'tag list keeps ~3 rows minimum',
      );
      // ... and the scrolled column extends past the panel bottom.
      final panelRect = tester.getRect(panel);
      expect(tagRect.bottom, greaterThan(panelRect.bottom));
      // The fallback actually scrolls.
      await tester.drag(find.text('Minimum rating'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('five trackers fit without overflow (1000x760)', (
      tester,
    ) async {
      await _pumpFilterBox(
        tester,
        surface: const Size(1000, 760),
        trackers: _fiveTrackers(),
      );

      expect(find.byType(DesktopLibraryFilterPanel), findsOneWidget);
      expect(find.text('Tracker Five'), findsOneWidget);
      final tagList = find.ancestor(
        of: find.text('All tags'),
        matching: find.byType(ListView),
      );
      expect(tagList, findsOneWidget);
      expect(
        tester.getRect(tagList).height,
        lessThan(150),
        reason: 'tag list shrank first',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Library display panel (desktop 1400x980)', () {
    testWidgets('radios update display mode, grid style, group style', (
      tester,
    ) async {
      final container = await _pumpLibrary(
        tester,
        surface: const Size(1400, 980),
      );
      await _openDisplayPanel(tester);

      expect(find.text('Display Mode'), findsOneWidget);

      await tester.tap(find.text('Comfortable grid'));
      await tester.pump();
      expect(
        container.read(libraryDisplayModeProvider),
        DisplayMode.comfortableGrid,
      );

      await tester.ensureVisible(find.text('Staggered'));
      await tester.tap(find.text('Staggered'));
      await tester.pump();
      expect(
        container.read(libraryGridStyleKeyProvider),
        LibraryGridStyle.staggered,
      );

      await tester.ensureVisible(find.text('Sections'));
      await tester.tap(find.text('Sections'));
      await tester.pump();
      expect(
        container.read(libraryGroupStyleKeyProvider),
        LibraryGroupStyle.headers,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('badge radios and toggles update their providers', (
      tester,
    ) async {
      final container = await _pumpLibrary(
        tester,
        surface: const Size(1400, 980),
      );
      await _openDisplayPanel(tester);

      await tester.ensureVisible(find.text('Hide'));
      await tester.tap(find.text('Hide'));
      await tester.pump();
      expect(container.read(unreadBadgeStyleProvider), UnreadBadgeMode.hidden);

      final languageToggle = find.ancestor(
        of: find.text('Language'),
        matching: find.byType(InkWell),
      );
      expect(languageToggle, findsOneWidget);
      await tester.ensureVisible(languageToggle);
      await tester.tap(languageToggle);
      await tester.pump();
      // The badge default is off, so tapping enables it.
      expect(container.read(languageBadgeProvider), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('body scrolls as one; no column scrolls inside itself', (
      tester,
    ) async {
      await _pumpLibrary(tester, surface: const Size(1400, 980));
      await _openDisplayPanel(tester);

      final panel = find.byType(DesktopLibraryDisplayPanel);
      expect(panel, findsOneWidget);
      expect(
        find.descendant(
          of: panel,
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      for (final key in [
        'displayColumn1',
        'displayColumn2',
        'displayColumn3',
      ]) {
        final column = find.byKey(ValueKey(key));
        expect(column, findsOneWidget);
        expect(
          find.descendant(
            of: column,
            matching: find.byType(SingleChildScrollView),
          ),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('grid style radios live in column 1', (tester) async {
      await _pumpLibrary(tester, surface: const Size(1400, 980));
      await _openDisplayPanel(tester);

      final first = find.byKey(const ValueKey('displayColumn1'));
      expect(first, findsOneWidget);
      expect(
        find.descendant(of: first, matching: find.text('Grid style')),
        findsOneWidget,
      );
      for (final label in ['Uniform', 'Non-uniform', 'Staggered']) {
        expect(
          find.descendant(of: first, matching: find.text(label)),
          findsOneWidget,
        );
      }
      final second = find.byKey(const ValueKey('displayColumn2'));
      expect(second, findsOneWidget);
      expect(
        find.descendant(of: second, matching: find.text('Uniform')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('display rows share the 36 px unified style', (tester) async {
      await _pumpLibrary(tester, surface: const Size(1400, 980));
      await _openDisplayPanel(tester);

      for (final label in [
        'Uniform',
        'Continue reading button',
        'Show number of items',
      ]) {
        expect(
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (w) => w is SizedBox && w.height == 36,
            ),
          ),
          findsOneWidget,
          reason: label,
        );
        expect(
          tester.widget<Text>(find.text(label)).style?.fontSize,
          14,
          reason: label,
        );
      }
      final heading = tester.widget<Text>(find.text('Grid style'));
      expect(heading.style?.fontSize, 13);
      expect(heading.style?.fontWeight, FontWeight.w600);
      expect(tester.takeException(), isNull);
    });

    testWidgets('display height sizes to content; column 3 needs no scroll', (
      tester,
    ) async {
      const surface = Size(1400, 980);
      final (_, panelRect) = await _openDisplayAndMeasure(tester, surface);
      // Content height, capped at the content-area height minus 140. The shell
      // reserves a 40 px title strip, so the cap here is 940 - 140 = 800.
      expect(panelRect.height, lessThanOrEqualTo(801.0));
      // Column 3's sliders are visible without scrolling ...
      final sliders = find.text('Columns (Portrait)');
      expect(sliders, findsOneWidget);
      final labelRect = tester.getRect(sliders);
      expect(labelRect.top, greaterThanOrEqualTo(panelRect.top - 1.0));
      expect(labelRect.bottom, lessThanOrEqualTo(panelRect.bottom + 1.0));
      // ... and the body has not scrolled.
      final scrollable = tester.widget<Scrollable>(
        find
            .descendant(
              of: find.byType(DesktopLibraryDisplayPanel),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scrollable.controller?.offset ?? 0, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('limit titles follows the display-mode rule', (tester) async {
      // Same rule as today's Display tab (`library_manga_display.dart`): only
      // modes that draw the title on the theme surface offer the cap. The
      // compact grid draws it on the art, so the toggle stays hidden there.
      await _pumpLibrary(tester, surface: const Size(1400, 980));
      await _openDisplayPanel(tester);
      expect(find.text('Limit titles to 2 lines'), findsNothing);

      await tester.tap(find.text('Comfortable grid'));
      await tester.pump();
      expect(find.text('Limit titles to 2 lines'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('AdaptiveSegments', () {
    testWidgets('long labels fall back to radio rows without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: AdaptiveSegments<String>(
                value: 'a',
                onChanged: (_) {},
                options: const [
                  SegmentOption(value: 'a', label: 'Any'),
                  SegmentOption(
                    value: 'b',
                    label: 'A very long option label that cannot fit',
                  ),
                  SegmentOption(value: 'c', label: 'No'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) => w is RadioListTile<dynamic>),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('radio fallback can select Any after Yes', (tester) async {
      bool? tapped;
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: AdaptiveSegments<bool?>(
                value: true,
                onChanged: (next) {
                  tapped = next;
                  calls++;
                },
                options: const [
                  SegmentOption(value: null, label: 'Any'),
                  SegmentOption(
                    value: true,
                    label: 'A very long included label that cannot fit',
                  ),
                  SegmentOption(
                    value: false,
                    label: 'Another very long excluded label that cannot fit',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) => w is RadioListTile<dynamic>),
        findsWidgets,
      );
      await tester.tap(find.text('Any'));
      await tester.pump();
      expect(calls, 1);
      expect(tapped, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('short labels stay segmented', (tester) async {
      var tapped = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: AdaptiveSegments<String>(
                value: 'a',
                onChanged: (next) => tapped = next,
                options: const [
                  SegmentOption(value: 'a', label: 'Any'),
                  SegmentOption(value: 'b', label: 'Yes'),
                  SegmentOption(value: 'c', label: 'No'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) => w is RadioListTile<dynamic>),
        findsNothing,
      );
      await tester.tap(find.text('Yes'));
      expect(tapped, 'b');
      expect(tester.takeException(), isNull);
    });

    testWidgets('short labels stay segmented at 200 px', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: AdaptiveSegments<String>(
                value: 'a',
                onChanged: (_) {},
                options: const [
                  SegmentOption(value: 'a', label: 'Any'),
                  SegmentOption(value: 'b', label: 'Yes'),
                  SegmentOption(value: 'c', label: 'No'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Control for the next test: the same width fits at default text size.
      expect(
        find.byWidgetPredicate((w) => w is RadioListTile<dynamic>),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('large text falls back to radio rows without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: SizedBox(
                width: 200,
                child: AdaptiveSegments<String>(
                  value: 'a',
                  onChanged: (_) {},
                  options: const [
                    SegmentOption(value: 'a', label: 'Any'),
                    SegmentOption(value: 'b', label: 'Yes'),
                    SegmentOption(value: 'c', label: 'No'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) => w is RadioListTile<dynamic>),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('segments expose selected state to semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: AdaptiveSegments<String>(
                value: 'b',
                onChanged: (_) {},
                options: const [
                  SegmentOption(value: 'a', label: 'Any'),
                  SegmentOption(value: 'b', label: 'Yes'),
                  SegmentOption(value: 'c', label: 'No'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final wrappers = tester
          .widgetList<Semantics>(
            find.descendant(
              of: find.byType(AdaptiveSegments<String>),
              matching: find.byType(Semantics),
            ),
          )
          .where((s) => (s.properties.label ?? '').isNotEmpty)
          .toList();
      expect(wrappers, hasLength(3));
      expect(wrappers.map((s) => s.properties.label).toList(), [
        'Any',
        'Yes',
        'No',
      ]);
      expect(wrappers.map((s) => s.properties.button).toList(), [
        true,
        true,
        true,
      ]);
      expect(wrappers.map((s) => s.properties.selected).toList(), [
        false,
        true,
        false,
      ]);
      expect(
        wrappers.map((s) => s.properties.inMutuallyExclusiveGroup).toList(),
        [true, true, true],
      );

      // And the selected flag reaches the semantics tree: walking up from
      // the tapped label's own node finds the selected segment wrapper ...
      SemanticsNode? selected;
      SemanticsNode? current = tester.getSemantics(find.text('Yes'));
      while (current != null) {
        if (current
                .getSemanticsData()
                .flagsCollection
                .isSelected
                .toBoolOrNull() ==
            true) {
          selected = current;
          break;
        }
        current = current.parent;
      }
      expect(selected, isNotNull);
      final selectedData = selected!.getSemanticsData();
      // Each option reads exactly once with the option text.
      expect(selectedData.label, 'Yes');
      expect(selectedData.flagsCollection.isButton, isTrue);
      // ... while the unselected labels have no selected ancestor.
      for (final label in ['Any', 'No']) {
        SemanticsNode? ancestor = tester.getSemantics(find.text(label));
        var found = false;
        while (ancestor != null) {
          if (ancestor
                  .getSemanticsData()
                  .flagsCollection
                  .isSelected
                  .toBoolOrNull() ==
              true) {
            found = true;
            break;
          }
          ancestor = ancestor.parent;
        }
        expect(found, isFalse, reason: label);
      }
      expect(tester.takeException(), isNull);
      handle.dispose();
    });
  });

  group('Library organizer (phone 412x900)', () {
    testWidgets('organizer has 4 tabs; filter tab shows short headings', (
      tester,
    ) async {
      await _pumpLibrary(tester, surface: const Size(412, 900));

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.filter_list_rounded),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final organizer = find.byType(LibraryMangaOrganizer);
      expect(organizer, findsOneWidget);
      expect(
        find.descendant(of: organizer, matching: find.byType(Tab)),
        findsNWidgets(4),
      );
      expect(find.widgetWithText(Tab, 'Filter'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Sort'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Display'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Group'), findsOneWidget);
      expect(find.text('Badges'), findsNothing);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('Started'), findsOneWidget);

      await tester.tap(find.widgetWithText(Tab, 'Display'));
      await tester.pumpAndSettle();
      expect(find.text('Badges'), findsOneWidget);
    });
  });
}
