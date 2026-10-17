// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_repository.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/recommends_row.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

void main() {
  String? pushedMangaId;

  Future<void> pump(WidgetTester tester, Size size) async {
    SharedPreferences.setMockInitialValues({'showRecommendations': true});
    final preferences = await SharedPreferences.getInstance();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    pushedMangaId = null;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: RecommendsRow(mangaId: 1, mangaTitle: 'Series'),
          ),
        ),
        GoRoute(
          path: '/recommends/:mangaId',
          builder: (_, state) {
            pushedMangaId = state.pathParameters['mangaId'];
            return const Scaffold(body: Text('RECOMMENDS SCREEN'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          mangaRecommendationsProvider(1).overrideWith(
            (ref) async => [
              for (var i = 0; i < 24; i++)
                Recommendation(title: 'Series $i', category: 'Test'),
            ],
          ),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('phone header is a tappable Suggestions row with one arrow', (
    tester,
  ) async {
    await pump(tester, const Size(412, 915));

    expect(find.text('Suggestions'), findsOneWidget);
    expect(find.text('See all'), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(find.byTooltip('See all'), findsOneWidget);

    await tester.tap(find.text('Suggestions'));
    await tester.pumpAndSettle();

    expect(pushedMangaId, '1');
    expect(find.text('RECOMMENDS SCREEN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide header keeps See all and paging arrows', (tester) async {
    await pump(tester, const Size(1400, 900));

    expect(find.text('See all'), findsOneWidget);
    expect(find.byType(IconButton), findsNWidgets(2));
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
    expect(find.byTooltip('See all'), findsNothing);

    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();

    expect(pushedMangaId, '1');
    expect(find.text('RECOMMENDS SCREEN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
