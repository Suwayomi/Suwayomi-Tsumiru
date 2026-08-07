// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/library_manga_grid_view.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import 'package:tsumiru/src/widgets/manga_cover/providers/manga_cover_providers.dart';

/// A title long enough to need several lines at any sane column width, so the
/// line-cap tests have something to actually cap.
const _longTitle = 'A Really Quite Extraordinarily Long Manga Title That Needs '
    'Several Lines To Show In Full Without Any Truncation At All';

/// Minimal MangaDto — [thumbnailUrl] null exercises the deterministic
/// no-cover branch (a real cover can't decode in a widget test).
Fragment$MangaDto _manga(int id, {String? thumbnailUrl, String? title}) =>
    Fragment$MangaDto(
      id: id,
      title: title ?? 'Manga $id',
      thumbnailUrl: thumbnailUrl,
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
      trackRecords:
          Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
      unreadCount: 2,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/$id',
    );

Future<void> _pump(
  WidgetTester tester, {
  required DisplayMode mode,
  required LibraryGridStyle style,
  double textScale = 1.0,
  int columns = 3,
  bool limitTitleLines = true,
  bool longTitles = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'libraryDisplayMode': DisplayMode.values.indexOf(mode),
    'libraryGridStyle': style.index,
    'limitTitleLines': limitTitleLines,
    // Fixed column count so the layout doesn't depend on the test surface size.
    'libraryPortraitColumns': columns,
    'libraryLandscapeColumns': columns,
    'languageBadge': true,
    'sourceBadge': true,
    'readProgressBar': true,
    'outlineOnCovers': true,
  });
  final sp = await SharedPreferences.getInstance();

  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: LibraryMangaGridView(
              items: [
                for (var i = 1; i <= 7; i++)
                  _manga(i, title: longTitles ? _longTitle : null),
              ],
              onOpen: (_) {},
              onLongPress: (_) {},
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  group('LibraryMangaGridView grid styles', () {
    for (final mode in [
      DisplayMode.grid,
      DisplayMode.comfortableGrid,
      DisplayMode.coverOnly,
    ]) {
      for (final style in LibraryGridStyle.values) {
        testWidgets('${mode.name} + ${style.name} lays out without exceptions',
            (tester) async {
          await _pump(tester, mode: mode, style: style);
          expect(tester.takeException(), isNull);
          expect(find.byType(MangaCoverGridTile), findsWidgets);
        });
      }
    }

    // Comfortable grid is the one mode with a title block competing with the
    // cover for a fixed cell, and it only overflows once text scale grows.
    // Boundary values only (min/max scale, min/max columns) — the cross
    // product isn't testing anything geometric, just that layout survives.
    for (final scale in [1.3, 3.0]) {
      for (final style in LibraryGridStyle.values) {
        for (final columns in [1, 8]) {
          for (final limit in [true, false]) {
            testWidgets(
                'comfortable ${style.name} survives scale $scale, '
                '$columns cols, limit=$limit', (tester) async {
              await _pump(
                tester,
                mode: DisplayMode.comfortableGrid,
                style: style,
                textScale: scale,
                columns: columns,
                limitTitleLines: limit,
              );
              expect(tester.takeException(), isNull);
            });
          }
        }
      }
    }

    testWidgets('uniform uses a plain SliverGrid', (tester) async {
      await _pump(
        tester,
        mode: DisplayMode.grid,
        style: LibraryGridStyle.uniform,
      );
      expect(find.byType(SliverGrid), findsOneWidget);
      expect(find.byType(SliverMasonryGrid), findsNothing);
      expect(find.byType(SliverAlignedGrid), findsNothing);
    });

    testWidgets('non-uniform uses the aligned grid', (tester) async {
      await _pump(
        tester,
        mode: DisplayMode.grid,
        style: LibraryGridStyle.nonUniform,
      );
      expect(find.byType(SliverAlignedGrid), findsOneWidget);
      expect(find.byType(SliverMasonryGrid), findsNothing);
    });

    testWidgets('staggered uses the masonry grid', (tester) async {
      await _pump(
        tester,
        mode: DisplayMode.grid,
        style: LibraryGridStyle.staggered,
      );
      expect(find.byType(SliverMasonryGrid), findsOneWidget);
      expect(find.byType(SliverAlignedGrid), findsNothing);
    });

    // Plain `test` (not testWidgets): a ProviderContainer's auto-dispose
    // scheduler leaves a pending timer, which trips the widget-test invariant.
    test('the style round-trips through the single persisted key', () async {
      for (final style in LibraryGridStyle.values) {
        SharedPreferences.setMockInitialValues({
          'libraryGridStyle': style.index,
        });
        final sp = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
        );
        addTearDown(container.dispose);
        expect(container.read(libraryGridStyleKeyProvider), style);
      }
    });

    test('an unset key falls back to uniform', () async {
      SharedPreferences.setMockInitialValues(const {});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(container.dispose);
      expect(
        container.read(libraryGridStyleKeyProvider),
        LibraryGridStyle.uniform,
      );
    });

    testWidgets('list modes ignore the grid style', (tester) async {
      await _pump(
        tester,
        mode: DisplayMode.list,
        style: LibraryGridStyle.staggered,
      );
      expect(find.byType(SliverMasonryGrid), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // A list row IS a Flex inside a fixed extent, so it's the one place a
    // vertical overflow can actually be reported. The extent has to grow with
    // both the platform text scale and the user's list-size slider.
    for (final mode in [DisplayMode.list, DisplayMode.descriptiveList]) {
      for (final scale in [1.0, 1.5, 2.0, 3.0]) {
        testWidgets('${mode.name} rows fit at text scale $scale',
            (tester) async {
          await _pump(tester, mode: mode, style: LibraryGridStyle.uniform,
              textScale: scale);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('title line limit', () {
    /// The rendered height of the first title paragraph, and its line cap.
    /// Found by TEXT, not by type — the badge counts are `Text`s too, and they
    /// come first in the tree.
    ({double height, int? maxLines}) title(WidgetTester tester) {
      final finder = find.text(_longTitle);
      expect(finder, findsWidgets, reason: 'no title rendered');
      final widget = tester.widget<Text>(finder.first);
      // A Text with a semanticsLabel wraps its RichText in Semantics, so the
      // paragraph isn't the Text's own render object — go find it.
      final para = tester.renderObject<RenderParagraph>(
        find
            .descendant(of: finder.first, matching: find.byType(RichText))
            .first,
      );
      return (height: para.size.height, maxLines: widget.maxLines);
    }

    // One scaled line of the comfortable-grid title (12sp × 1.5).
    const line = 18.0;

    for (final style in LibraryGridStyle.values) {
      testWidgets('comfortable ${style.name} caps at 2 lines when limited',
          (tester) async {
        await _pump(
          tester,
          mode: DisplayMode.comfortableGrid,
          style: style,
          limitTitleLines: true,
          longTitles: true,
        );
        final t = title(tester);
        expect(t.maxLines, 2);
        expect(t.height, line * 2);
      });
    }

    for (final style in [
      LibraryGridStyle.nonUniform,
      LibraryGridStyle.staggered,
    ]) {
      testWidgets('comfortable ${style.name} wraps in full when unlimited',
          (tester) async {
        // A self-sizing tile can grow, so the whole title must show — and Skia
        // collapses `ellipsis + maxLines: null` back to one line.
        await _pump(
          tester,
          mode: DisplayMode.comfortableGrid,
          style: style,
          limitTitleLines: false,
          longTitles: true,
        );
        final t = title(tester);
        expect(t.maxLines, isNull);
        expect(t.height, greaterThan(line * 2),
            reason: 'unlimited must wrap past the 2-line cap');
      });
    }

    testWidgets('comfortable uniform grows to the cell cap when unlimited',
        (tester) async {
      // A uniform cell's height is fixed by its aspect ratio, so the title takes
      // as many whole lines as its slot holds rather than wrapping unbounded.
      await _pump(
        tester,
        mode: DisplayMode.comfortableGrid,
        style: LibraryGridStyle.uniform,
        limitTitleLines: false,
        longTitles: true,
      );
      final t = title(tester);
      expect(t.maxLines, isNotNull);
      expect(t.maxLines!, greaterThan(2));
      expect(tester.takeException(), isNull);
    });

    for (final mode in [DisplayMode.list, DisplayMode.descriptiveList]) {
      testWidgets('${mode.name} caps its title when limited', (tester) async {
        await _pump(
          tester,
          mode: mode,
          style: LibraryGridStyle.uniform,
          limitTitleLines: true,
          longTitles: true,
        );
        expect(title(tester).maxLines, isNotNull);
      });

      testWidgets('${mode.name} wraps in full when unlimited', (tester) async {
        await _pump(
          tester,
          mode: mode,
          style: LibraryGridStyle.uniform,
          limitTitleLines: false,
          longTitles: true,
        );
        expect(title(tester).maxLines, isNull);
        expect(tester.takeException(), isNull);
      });

      testWidgets('${mode.name} rows self-size when unlimited',
          (tester) async {
        // A fixed extent would clip the very lines the setting reveals.
        await _pump(
          tester,
          mode: mode,
          style: LibraryGridStyle.uniform,
          limitTitleLines: false,
          longTitles: true,
        );
        expect(find.byType(SliverFixedExtentList), findsNothing);
        expect(find.byType(SliverList), findsOneWidget);
      });
    }
  });

  group('MangaCoverGridTile sizing', () {
    /// A deliberately over-tall 120×400 slot: a uniform tile fills it, a
    /// freeform tile must take the cover's own height instead.
    Future<double> cardHeight(
      WidgetTester tester,
      LibraryGridStyle style,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 120,
              height: 400,
              child: MangaCoverGridTile(
                manga: _manga(1),
                showBadges: false,
                gridStyle: style,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      return tester.getSize(find.byType(Card)).height;
    }

    testWidgets('a uniform tile fills the cell it is given', (tester) async {
      expect(await cardHeight(tester, LibraryGridStyle.uniform), 400);
    });

    /// Where the cover sits inside an over-tall slot — the aligned grid stretches
    /// every tile in a row to its tallest sibling, so this is what decides
    /// whether non-uniform reads as flush-bottom or flush-top.
    Future<Rect> cardRect(
      WidgetTester tester,
      LibraryGridStyle style, {
      bool titleBelow = false,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 120,
              height: 400,
              child: MangaCoverGridTile(
                manga: _manga(1),
                showBadges: false,
                titleBelow: titleBelow,
                gridStyle: style,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      return tester.getRect(find.byType(Card));
    }

    testWidgets('non-uniform bottom-aligns its cover', (tester) async {
      final rect = await cardRect(tester, LibraryGridStyle.nonUniform);
      expect(rect.bottom, 400);
      expect(rect.top, greaterThan(0));
    });

    testWidgets('non-uniform bottom-aligns the cover+title block too',
        (tester) async {
      final rect =
          await cardRect(tester, LibraryGridStyle.nonUniform, titleBelow: true);
      // The title sits under the card, so the CARD stops short of the baseline —
      // but the block as a whole is still anchored to the bottom.
      expect(rect.bottom, lessThan(400));
      expect(rect.top, greaterThan(0));
      final column = tester.getRect(
        find.descendant(
          of: find.byType(MangaCoverGridTile),
          matching: find.byType(Column),
        ).first,
      );
      expect(column.bottom, 400);
    });

    testWidgets('staggered top-aligns (its tiles are never stretched)',
        (tester) async {
      final rect = await cardRect(tester, LibraryGridStyle.staggered);
      expect(rect.top, 0);
      expect(rect.bottom, lessThan(400));
    });

    for (final style in [
      LibraryGridStyle.nonUniform,
      LibraryGridStyle.staggered,
    ]) {
      testWidgets('a ${style.name} tile sizes itself from the cover',
          (tester) async {
        final height = await cardHeight(tester, style);
        // Card margin is 4dp per side, so the cover is 112 wide and — with no
        // art to measure — falls back to the 2:3 book ratio.
        expect(height, lessThan(400));
        expect(height - 8, closeTo(112 * 1.5, 1));
      });
    }
  });

  group('comfortable grid title', () {
    /// Regression: a hardcoded 44dp title block sized against an unscaled 12sp
    /// font stopped fitting as soon as the platform text scale rose.
    Future<void> pumpComfortable(
      WidgetTester tester, {
      required double textScale,
      required bool limitLines,
      double cellHeight = 218,
    }) async {
      await tester.pumpWidget(MaterialApp(
        // Inside MaterialApp so the real surface size is kept — only the text
        // scale is overridden.
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 135,
                  height: cellHeight,
                  child: MangaCoverGridTile(
                    manga: _manga(1),
                    showBadges: false,
                    titleBelow: true,
                    limitTitleLines: limitLines,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    for (final scale in [1.0, 1.3, 1.5, 2.0]) {
      testWidgets('does not overflow at text scale $scale', (tester) async {
        await pumpComfortable(tester, textScale: scale, limitLines: true);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('does not overflow with the line limit off', (tester) async {
      await pumpComfortable(tester, textScale: 2.0, limitLines: false);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the title block grows with the text scale', (tester) async {
      await pumpComfortable(tester, textScale: 1.0, limitLines: true);
      final small = 218 - tester.getSize(find.byType(Card)).height;
      await pumpComfortable(tester, textScale: 1.5, limitLines: true);
      final large = 218 - tester.getSize(find.byType(Card)).height;
      // A bigger font reserves more room for the title, taking it from the cover
      // instead of overflowing the cell.
      expect(large, greaterThan(small));
    });
  });
}
