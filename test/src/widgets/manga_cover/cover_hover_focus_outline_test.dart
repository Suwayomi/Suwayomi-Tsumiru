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

Future<void> _hoverCenter(WidgetTester tester, Finder finder) async {
  final gesture =
      await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 1);
  addTearDown(gesture.removePointer);
  await gesture.addPointer(location: Offset.zero);
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pump();
}

void main() {
  group('grid cover outline', () {
    testWidgets('hover shows a primary 2px border', (tester) async {
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
      final side = _cardSide(tester);
      expect(side.color, _primary(tester, find.byType(Card)));
      expect(side.width, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard focus shows the border, pointer tap does not',
        (tester) async {
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
      final focusNode =
          tester.widget<InkResponse>(find.byType(InkResponse)).focusNode!;

      await tester.tap(find.byType(MangaCoverGridTile));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      expect(_cardSide(tester), BorderSide.none);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      final side = _cardSide(tester);
      expect(side.color, _primary(tester, find.byType(Card)));
      expect(side.width, 2);
      expect(pressed, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a selected cover has a 3px border', (tester) async {
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
      final side = _cardSide(tester);
      expect(side.color, _primary(tester, find.byType(Card)));
      expect(side.width, 3);
      expect(tester.takeException(), isNull);
    });
  });

  group('list row outline', () {
    testWidgets('hover outlines the thumbnail at 2px', (tester) async {
      await _pump(
        tester,
        MangaCoverListTile(
          manga: _manga(1),
          showBadges: false,
          onPressed: () {},
        ),
      );
      expect(_thumbnailBorder(tester), isNull);

      await _hoverCenter(tester, find.byType(MangaCoverListTile));
      final border = _thumbnailBorder(tester);
      expect(border?.top.color, _primary(tester, find.byType(Row).first));
      expect(border?.top.width, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard focus outlines the thumbnail, tap does not',
        (tester) async {
      await _pump(
        tester,
        MangaCoverListTile(
          manga: _manga(1),
          showBadges: false,
          onPressed: () {},
        ),
      );
      final focusNode =
          tester.widget<InkWell>(find.byType(InkWell).first).focusNode!;

      await tester.tap(find.byType(MangaCoverListTile));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      expect(_thumbnailBorder(tester), isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(_thumbnailBorder(tester)?.top.width, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a selected row outlines the thumbnail at 3px', (tester) async {
      await _pump(
        tester,
        MangaCoverListTile(
          manga: _manga(1),
          showBadges: false,
          selected: true,
          onPressed: () {},
        ),
      );
      final border = _thumbnailBorder(tester);
      expect(
        border?.top.color,
        _primary(tester, find.byType(MangaCoverListTile)),
      );
      expect(border?.top.width, 3);
      expect(tester.takeException(), isNull);
    });
  });

  group('descriptive row outline', () {
    testWidgets('row hover outlines the cover, selection uses 3px',
        (tester) async {
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
      expect(_cardSide(tester).width, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selection reaches the embedded cover', (tester) async {
      await _pump(
        tester,
        MangaCoverDescriptiveListTile(
          manga: _manga(1),
          showBadges: false,
          selected: true,
          onPressed: () {},
        ),
      );
      final side = _cardSide(tester);
      expect(
        side.color,
        _primary(tester, find.byType(MangaCoverDescriptiveListTile)),
      );
      expect(side.width, 3);
      expect(tester.takeException(), isNull);
    });
  });

  group('keyboard activation and traversal', () {
    testWidgets('Enter opens the focused cover', (tester) async {
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

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Space activates the focused cover', (tester) async {
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

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(pressed, 1);
      expect(tester.takeException(), isNull);
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
  });
}
