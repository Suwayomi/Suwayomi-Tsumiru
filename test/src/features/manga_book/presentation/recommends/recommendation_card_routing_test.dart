// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_provider.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/recommends/recommendation_card.dart';

import '../../reader/reader_test_fixtures.dart';

MangaDto _entry(int id, String title) =>
    testManga().copyWith.call(id: id, title: title);

void main() {
  group('RecommendationCard tap routing', () {
    String? pushedMangaId;

    Future<void> pump(
      WidgetTester tester,
      String recTitle, {
      required List<MangaDto>? library,
      bool failLookup = false,
    }) async {
      pushedMangaId = null;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Center(
                child: RecommendationCard(
                  rec: Recommendation(title: recTitle, category: 'c'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/manga/:mangaId',
            builder: (_, state) {
              pushedMangaId = state.pathParameters['mangaId'];
              return const Scaffold(body: Text('SERIES PAGE'));
            },
          ),
          GoRoute(
            path: '/global-search',
            builder: (_, _) => const Scaffold(body: Text('GLOBAL SEARCH')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            if (failLookup)
              libraryMangaListProvider.overrideWith((ref) async {
                throw StateError('lookup failed');
              })
            else
              libraryMangaListProvider.overrideWith((ref) async => library),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('title match opens the series page, not search', (
      tester,
    ) async {
      await pump(
        tester,
        '  oNe PiEcE ',
        library: [_entry(7, 'One Piece'), _entry(9, 'Berserk')],
      );

      await tester.tap(find.byType(RecommendationCard));
      await tester.pumpAndSettle();

      expect(find.text('SERIES PAGE'), findsOneWidget);
      expect(find.text('GLOBAL SEARCH'), findsNothing);
      expect(pushedMangaId, '7');
      expect(tester.takeException(), isNull);
    });

    testWidgets('no match falls back to global search', (tester) async {
      await pump(
        tester,
        'Unknown Title XYZ',
        library: [_entry(7, 'One Piece')],
      );

      await tester.tap(find.byType(RecommendationCard));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsOneWidget);
      expect(find.text('SERIES PAGE'), findsNothing);
      expect(pushedMangaId, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty library falls back to global search', (tester) async {
      await pump(tester, 'One Piece', library: const []);

      await tester.tap(find.byType(RecommendationCard));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsOneWidget);
      expect(find.text('SERIES PAGE'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lookup error falls back to global search', (tester) async {
      await pump(
        tester,
        'One Piece',
        library: [_entry(7, 'One Piece')],
        failLookup: true,
      );

      await tester.tap(find.byType(RecommendationCard));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsOneWidget);
      expect(find.text('SERIES PAGE'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
