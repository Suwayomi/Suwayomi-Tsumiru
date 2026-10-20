// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
import 'package:tsumiru/src/widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import 'package:tsumiru/src/widgets/manga_cover/providers/manga_cover_providers.dart';

/// A title long enough to need several lines at any sane column width, so the
/// line-cap tests have something to actually cap.
const _longTitle =
    'A Really Quite Extraordinarily Long Manga Title That Needs '
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
      trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
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

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
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
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('every grid style lays out without exceptions', (tester) async {
    for (final mode in [
      DisplayMode.grid,
      DisplayMode.comfortableGrid,
      DisplayMode.coverOnly,
    ]) {
      for (final style in LibraryGridStyle.values) {
        await _pump(tester, mode: mode, style: style);
        expect(tester.takeException(), isNull);
        expect(find.byType(MangaCoverGridTile), findsWidgets);
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  // Plain `test` (not testWidgets): a ProviderContainer's auto-dispose
  // scheduler leaves a pending timer, which trips the widget-test invariant.
  test('the style round-trips through the single persisted key', () async {
    for (final style in LibraryGridStyle.values) {
      SharedPreferences.setMockInitialValues({'libraryGridStyle': style.index});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(container.dispose);
      expect(container.read(libraryGridStyleKeyProvider), style);
    }
  });

  testWidgets('comfortable grid title caps at 2 lines when limited', (
    tester,
  ) async {
    // One scaled line of the comfortable-grid title (12sp × 1.5).
    const line = 18.0;
    for (final style in LibraryGridStyle.values) {
      await _pump(
        tester,
        mode: DisplayMode.comfortableGrid,
        style: style,
        limitTitleLines: true,
        longTitles: true,
      );
      final finder = find.text(_longTitle);
      expect(finder, findsWidgets, reason: 'no title rendered');
      final widget = tester.widget<Text>(finder.first);
      final para = tester.renderObject<RenderParagraph>(
        find
            .descendant(of: finder.first, matching: find.byType(RichText))
            .first,
      );
      expect(widget.maxLines, 2);
      expect(para.size.height, line * 2);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
