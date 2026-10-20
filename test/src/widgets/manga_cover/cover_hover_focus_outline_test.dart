// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import 'package:tsumiru/src/widgets/manga_cover/list/manga_cover_descriptive_list_tile.dart';
import 'package:tsumiru/src/widgets/manga_cover/list/manga_cover_list_tile.dart';

Fragment$MangaDto _manga(int id) => Fragment$MangaDto(
  id: id,
  title: 'Test Manga $id',
  thumbnailUrl: null,
  bookmarkCount: 0,
  chapters: Fragment$MangaDto$chapters(totalCount: 4),
  downloadCount: 0,
  genre: const [],
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: const [],
  source: Fragment$MangaDto$source(
    id: '1',
    name: 'Test Source',
    displayName: 'Test Source',
    lang: 'en',
    iconUrl: '/icon.png',
    contentWarning: Enum$ContentWarning.SAFE,
    $extension: Fragment$MangaDto$source$extension(isObsolete: false),
  ),
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  unreadCount: 2,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/$id',
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

BorderSide _cardSide(WidgetTester tester) {
  final card = tester.widget<Card>(find.byType(Card));
  return (card.shape! as RoundedRectangleBorder).side;
}

Border? _thumbnailBorder(WidgetTester tester) {
  final matches = tester
      .widgetList<Container>(
        find.byWidgetPredicate(
          (w) => w is Container && w.foregroundDecoration is BoxDecoration,
        ),
      )
      .toList();
  if (matches.isEmpty) return null;
  final decoration = matches.single.foregroundDecoration! as BoxDecoration;
  return decoration.border as Border?;
}

Color _primary(WidgetTester tester, Finder scope) =>
    Theme.of(tester.element(scope)).colorScheme.primary;

TestGesture? _mouse;

Future<TestGesture> _ensureMouse(WidgetTester tester) async {
  if (_mouse == null) {
    _mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await _mouse!.addPointer(location: Offset.zero);
    addTearDown(_mouse!.removePointer);
  }
  return _mouse!;
}

Future<void> _hoverCenter(WidgetTester tester, Finder finder) async {
  final mouse = await _ensureMouse(tester);
  await mouse.moveTo(tester.getCenter(finder));
  await tester.pump();
}

/// Moves the mouse off the cover so the next phase starts unhovered.
Future<void> _parkMouse(WidgetTester tester) async {
  final mouse = await _ensureMouse(tester);
  await mouse.moveTo(const Offset(790, 590));
  await tester.pump();
}

void main() {
  testWidgets('grid and list outline states', (tester) async {
    _mouse = null;
    // Grid: hover outlines the card in the primary colour.
    await _pump(
      tester,
      SizedBox(
        width: 160,
        child: MangaCoverGridTile(
          manga: _manga(1),
          showBadges: false,
          onPressed: () {},
        ),
      ),
    );
    expect(_cardSide(tester), BorderSide.none);
    await _hoverCenter(tester, find.byType(MangaCoverGridTile));
    expect(_cardSide(tester).color, _primary(tester, find.byType(Card)));
    expect(tester.takeException(), isNull);

    // Grid: keyboard focus shows the border; a pointer tap does not.
    await _parkMouse(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    var pressed = 0;
    await _pump(
      tester,
      SizedBox(
        width: 160,
        child: MangaCoverGridTile(
          manga: _manga(1),
          showBadges: false,
          onPressed: () => pressed++,
        ),
      ),
    );
    final gridFocus = tester
        .widget<InkResponse>(find.byType(InkResponse))
        .focusNode!;
    await tester.tap(find.byType(MangaCoverGridTile));
    await tester.pump();
    expect(gridFocus.hasFocus, isTrue);
    expect(_cardSide(tester), BorderSide.none);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(_cardSide(tester).color, _primary(tester, find.byType(Card)));
    expect(pressed, 1);
    expect(tester.takeException(), isNull);

    // Grid: a selected cover outlines the card.
    await _parkMouse(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      SizedBox(
        width: 160,
        child: MangaCoverGridTile(
          manga: _manga(1),
          showBadges: false,
          selected: true,
          onPressed: () {},
        ),
      ),
    );
    expect(_cardSide(tester).color, _primary(tester, find.byType(Card)));
    expect(tester.takeException(), isNull);

    // List: hover outlines the thumbnail in the primary colour.
    await _parkMouse(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      MangaCoverListTile(manga: _manga(1), showBadges: false, onPressed: () {}),
    );
    expect(_thumbnailBorder(tester), isNull);
    await _hoverCenter(tester, find.byType(MangaCoverListTile));
    expect(
      _thumbnailBorder(tester)?.top.color,
      _primary(tester, find.byType(Row).first),
    );
    expect(tester.takeException(), isNull);

    // List: keyboard focus outlines the thumbnail; tap does not.
    await _parkMouse(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      MangaCoverListTile(manga: _manga(1), showBadges: false, onPressed: () {}),
    );
    final listFocus = tester
        .widget<InkWell>(find.byType(InkWell).first)
        .focusNode!;
    await tester.tap(find.byType(MangaCoverListTile));
    await tester.pump();
    expect(listFocus.hasFocus, isTrue);
    expect(_thumbnailBorder(tester), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(_thumbnailBorder(tester), isNotNull);
    expect(tester.takeException(), isNull);

    // List: a selected row outlines the thumbnail.
    await _parkMouse(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      MangaCoverListTile(
        manga: _manga(1),
        showBadges: false,
        selected: true,
        onPressed: () {},
      ),
    );
    expect(
      _thumbnailBorder(tester)?.top.color,
      _primary(tester, find.byType(MangaCoverListTile)),
    );
    expect(tester.takeException(), isNull);

    // Descriptive row: hover outlines the cover, selection too.
    await _parkMouse(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      MangaCoverDescriptiveListTile(
        manga: _manga(1),
        showBadges: false,
        onPressed: () {},
      ),
    );
    expect(_cardSide(tester), BorderSide.none);
    await _hoverCenter(tester, find.byType(MangaCoverDescriptiveListTile));
    expect(_cardSide(tester).color, _primary(tester, find.byType(Card)));
    expect(tester.takeException(), isNull);

    await _parkMouse(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      MangaCoverDescriptiveListTile(
        manga: _manga(1),
        showBadges: false,
        selected: true,
        onPressed: () {},
      ),
    );
    expect(
      _cardSide(tester).color,
      _primary(tester, find.byType(MangaCoverDescriptiveListTile)),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Enter and Space activate the focused cover', (tester) async {
    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      var pressed = 0;
      await _pump(
        tester,
        SizedBox(
          width: 160,
          child: MangaCoverGridTile(
            manga: _manga(1),
            showBadges: false,
            onPressed: () => pressed++,
          ),
        ),
      );
      tester
          .widget<InkResponse>(find.byType(InkResponse))
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(pressed, 1, reason: '$key');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('arrow keys move focus across the row', (tester) async {
    await _pump(
      tester,
      Row(
        children: [
          for (final id in [1, 2])
            SizedBox(
              width: 150,
              child: MangaCoverGridTile(
                manga: _manga(id),
                showBadges: false,
                onPressed: () {},
              ),
            ),
        ],
      ),
    );
    final nodes = tester
        .widgetList<InkResponse>(find.byType(InkResponse))
        .map((w) => w.focusNode!)
        .toList();
    nodes.first.requestFocus();
    await tester.pump();
    expect(nodes.first.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(nodes.last.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
