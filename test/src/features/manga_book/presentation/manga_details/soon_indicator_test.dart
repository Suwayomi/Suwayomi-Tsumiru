// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/manga_cover/list/manga_cover_descriptive_list_tile.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Minimal MangaDto for widget tests — only required fields filled.
Fragment$MangaDto _minimalManga({String title = 'Test Manga'}) =>
    Fragment$MangaDto(
      id: 1,
      title: title,
      bookmarkCount: 0,
      chapters: Fragment$MangaDto$chapters(totalCount: 0),
      downloadCount: 0,
      genre: const [],
      inLibrary: false,
      inLibraryAt: '0',
      initialized: true,
      meta: const [],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords: Fragment$MangaDto$trackRecords(
        totalCount: 0,
        nodes: const [],
      ),
      unreadCount: 0,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/1',
    );

Widget _app(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('MangaCoverDescriptiveListTile belowStatus', () {
    testWidgets('renders belowStatus widget when provided', (tester) async {
      const soonKey = Key('soon-indicator');

      await tester.pumpWidget(
        _app(
          MangaCoverDescriptiveListTile(
            manga: _minimalManga(),
            showBadges: false,
            belowStatus: const Text('Coming soon', key: soonKey),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(soonKey), findsOneWidget);
      expect(find.text('Coming soon'), findsOneWidget);
    });

    testWidgets('renders nothing below status when belowStatus is null', (
      tester,
    ) async {
      const soonKey = Key('soon-indicator');

      await tester.pumpWidget(
        _app(
          MangaCoverDescriptiveListTile(
            manga: _minimalManga(),
            showBadges: false,
            // belowStatus defaults to null
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(soonKey), findsNothing);
    });

    testWidgets('library/browse callers are visually unchanged (null default)', (
      tester,
    ) async {
      // Simulates a library list call: no belowStatus passed.
      // showBadges: false avoids Riverpod deps in MangaBadgesRow/MangaChipsRow.
      await tester.pumpWidget(
        _app(
          MangaCoverDescriptiveListTile(
            manga: _minimalManga(title: 'Library Manga'),
            showBadges: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Library Manga'), findsOneWidget);
    });

    testWidgets('tapping soon indicator triggers the provided onTap', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        _app(
          MangaCoverDescriptiveListTile(
            manga: _minimalManga(),
            showBadges: false,
            belowStatus: GestureDetector(
              onTap: () => tapped = true,
              child: const Text('Soon'),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Soon'));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });
}
