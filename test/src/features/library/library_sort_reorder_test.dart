// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Regression guard for the sort-change crash: changing the library sort
// re-orders every tile under a live sliver, and masonry
// (LibraryGridStyle.staggered) keeps each child's packed offset and column on
// its render object. A re-order used to leave it holding children whose
// layoutOffset was null, which RenderSliverMasonryGrid.performLayout
// dereferences unconditionally — it threw mid-layout and left the grid blank.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/library_manga_grid_view.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

/// Long enough that the sliver materialises only a prefix of the list, which
/// [_expectPrefixOnly] asserts rather than assumes: a re-order has to be able to
/// push live children past the last index that has a known layout offset, and a
/// list that fits entirely in the viewport cache never does.
const _itemCount = 200;

/// Minimal MangaDto — a null [thumbnailUrl] takes the deterministic no-cover
/// branch, since a real cover can't decode in a widget test.
Fragment$MangaDto _manga(int id) => Fragment$MangaDto(
  id: id,
  title: 'Manga $id',
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
  trackRecords: Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
  unreadCount: 2,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/$id',
);

/// The child index range the grid's sliver currently has laid out, or null when
/// it has none — which is the crash's visible symptom, a blank grid, and is not
/// something [WidgetTester.takeException] would report on its own.
({int first, int last})? _liveRange(WidgetTester tester) {
  final adaptor = tester.allRenderObjects
      .whereType<RenderSliverMultiBoxAdaptor>()
      .first;
  final first = adaptor.firstChild;
  final last = adaptor.lastChild;
  if (first == null || last == null) return null;
  return (first: adaptor.indexOf(first), last: adaptor.indexOf(last));
}

void _expectNotBlank(WidgetTester tester, String when) {
  expect(_liveRange(tester), isNotNull, reason: 'the grid went blank $when');
}

/// Guards the premise of the whole file. If a layout change ever lets the
/// viewport cache hold all [_itemCount] tiles, every re-ordered child keeps a
/// known layout offset and these tests would pass without exercising anything.
///
/// Indexes are item indexes for every style except nonUniform, whose sliver
/// lays out rows; the bound holds either way.
void _expectPrefixOnly(WidgetTester tester) {
  final live = _liveRange(tester);
  expect(live, isNotNull);
  expect(
    live!.last,
    lessThan(_itemCount - 1),
    reason:
        'the sliver must materialise only a prefix for the re-order below '
        'to be representative',
  );
}

/// Re-pumps the same grid with a new item order. The provider overrides are
/// built once and reused, so only `items` changes between pumps — a fresh
/// override would re-create the preference notifiers instead of re-ordering.
Future<Future<void> Function(List<Fragment$MangaDto>)> _harness(
  WidgetTester tester, {
  required DisplayMode mode,
  required LibraryGridStyle style,
}) async {
  SharedPreferences.setMockInitialValues({
    'libraryDisplayMode': DisplayMode.values.indexOf(mode),
    'libraryGridStyle': style.index,
    'limitTitleLines': true,
    // Fixed column count so the layout doesn't depend on the test surface size.
    'libraryPortraitColumns': 3,
    'libraryLandscapeColumns': 3,
    'languageBadge': true,
    'sourceBadge': true,
    'outlineOnCovers': true,
  });
  final sp = await SharedPreferences.getInstance();
  final overrides = [sharedPreferencesProvider.overrideWithValue(sp)];

  return (items) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LibraryMangaGridView(
              items: items,
              onOpen: (_) {},
              onLongPress: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  };
}

void main() {
  final ascending = [for (var i = 1; i <= _itemCount; i++) _manga(i)];
  // Stands in for a sort change, and it has to be a PARTIAL re-order to be
  // representative: when every live child moves, masonry's own
  // children-re-ordered fallback discards the lot and re-packs from index 0, so
  // a plain reverse never reproduced the bug. Pinning the first item leaves one
  // child holding a valid layout offset — the fallback stays quiet — while every
  // other live child lands past the last index that has one.
  final reordered = [ascending.first, ...ascending.skip(1).toList().reversed];

  Future<void> expectCleanReorder(
    WidgetTester tester, {
    required DisplayMode mode,
    required LibraryGridStyle style,
  }) async {
    final pump = await _harness(tester, mode: mode, style: style);

    await pump(ascending);
    expect(tester.takeException(), isNull, reason: 'initial layout');
    _expectPrefixOnly(tester);

    await pump(reordered);
    expect(tester.takeException(), isNull, reason: 're-order');
    _expectNotBlank(tester, 'after the re-order');

    // And back again — this transition re-uses the children the first re-order
    // just laid out.
    await pump(ascending);
    expect(tester.takeException(), isNull, reason: 're-order back');
    _expectNotBlank(tester, 'after re-ordering back');
  }

  group('re-sorting the library re-lays out cleanly', () {
    // Only the grid modes read the grid style, and staggered is the one that
    // used to crash — so it's checked against every grid mode, plus uniform
    // as a sanity case that a style never affected by the bug stays clean.
    for (final mode in [
      DisplayMode.grid,
      DisplayMode.comfortableGrid,
      DisplayMode.coverOnly,
    ]) {
      for (final style in [
        LibraryGridStyle.staggered,
        LibraryGridStyle.uniform,
      ]) {
        testWidgets('${mode.name} + ${style.name}', (tester) async {
          await expectCleanReorder(tester, mode: mode, style: style);
        });
      }
    }

    // The list modes ignore the grid style, so one pass each is the whole
    // matrix: they go through SliverFixedExtentList/SliverList, which re-derive
    // or rewrite layout offsets and were never affected.
    for (final mode in [DisplayMode.list, DisplayMode.descriptiveList]) {
      testWidgets(mode.name, (tester) async {
        await expectCleanReorder(
          tester,
          mode: mode,
          style: LibraryGridStyle.uniform,
        );
      });
    }
  });
}
