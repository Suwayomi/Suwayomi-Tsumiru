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
import 'package:tsumiru/src/features/library/presentation/library/widgets/library_manga_grid_view.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/theme/app_theme_builder.dart';
import 'package:tsumiru/src/widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import 'package:tsumiru/src/widgets/manga_cover/list/manga_cover_list_tile.dart';

/// Minimal MangaDto — [thumbnailUrl] null exercises the deterministic
/// no-cover branch (a real cover can't decode in a widget test).
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
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  unreadCount: 2,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/$id',
);

/// Pumps the library grid the way desktop Library shows it: 1400x900, the
/// always-visible themed scrollbar, and the scroll view run to the content
/// area's right edge (the desktop [_groupedBody] shape). Returns the scroll
/// controller so tests can assert the content actually scrolls.
Future<ScrollController> _pumpDesktop(
  WidgetTester tester, {
  required DisplayMode mode,
  int itemCount = 60,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({
    'libraryDisplayMode': DisplayMode.values.indexOf(mode),
    'libraryGridStyle': LibraryGridStyle.uniform.index,
    'limitTitleLines': true,
    'libraryPortraitColumns': 4,
    'libraryLandscapeColumns': 4,
    'languageBadge': true,
    'sourceBadge': true,
    'readProgressBar': true,
    'outlineOnCovers': true,
  });
  final sp = await SharedPreferences.getInstance();
  final controller = ScrollController();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.light().copyWith(
          scrollbarTheme: wideScreenScrollbarTheme(const ColorScheme.light()),
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: PrimaryScrollController(
              controller: controller,
              child: Scrollbar(
                controller: controller,
                child: LibraryMangaGridView(
                  items: [for (var i = 1; i <= itemCount; i++) _manga(i)],
                  onOpen: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

/// The themed thumb paints inside the trailing edge of the scrollable (8px,
/// 10px on hover), so no content may enter that trailing 10px strip.
void _expectNoThumbOverlap(WidgetTester tester, Finder tiles) {
  expect(tiles, findsWidgets);
  final scrollableRect = tester.getRect(find.byType(Scrollable).first);
  final thumbStrip = Rect.fromLTWH(
    scrollableRect.right - 10,
    scrollableRect.top,
    10,
    scrollableRect.height,
  );
  for (final element in tiles.evaluate()) {
    final box = element.renderObject! as RenderBox;
    final tileRect = box.localToGlobal(Offset.zero) & box.size;
    expect(
      thumbStrip.overlaps(tileRect),
      isFalse,
      reason: 'thumb strip $thumbStrip overlaps tile $tileRect',
    );
  }
}

void main() {
  group('Library desktop scrollbar gutter', () {
    for (final mode in [
      DisplayMode.grid,
      DisplayMode.comfortableGrid,
      DisplayMode.coverOnly,
    ]) {
      testWidgets('${mode.name} grid keeps covers off the thumb', (
        tester,
      ) async {
        final controller = await _pumpDesktop(tester, mode: mode);
        expect(tester.takeException(), isNull);
        expect(controller.position.maxScrollExtent, greaterThan(0));
        _expectNoThumbOverlap(tester, find.byType(MangaCoverGridTile));
      });
    }

    testWidgets('list rows keep off the thumb', (tester) async {
      final controller = await _pumpDesktop(
        tester,
        mode: DisplayMode.list,
      );
      expect(tester.takeException(), isNull);
      expect(controller.position.maxScrollExtent, greaterThan(0));
      _expectNoThumbOverlap(tester, find.byType(MangaCoverListTile));
    });
  });
}
