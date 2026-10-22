import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:tsumiru/src/features/manga_book/data/recommendations/providers/anilist_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_repository.dart';
import 'package:tsumiru/src/features/manga_book/presentation/recommends/recommends_browse_screen.dart';
import 'package:tsumiru/src/features/manga_book/presentation/recommends/recommends_screen.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

void main() {
  const provider = AnilistProvider();
  for (final browse in [false, true]) {
    for (final error in [
      const RecommendationHttpException(403),
      TimeoutException("Timed out"),
      const RecommendationServiceUnavailable(),
    ]) {
      testWidgets('${browse ? 'Grid' : 'Sections'} explains $error', (
        tester,
      ) async {
        final client = http.Client();
        addTearDown(client.close);
        await tester.pumpWidget(
          ProviderScope(
            retry: (_, _) => null,
            overrides: [
              recommendationSetupProvider(1).overrideWith(
                (ref) async => (
                  ctx: RecommendationContext(
                    title: 'Example',
                    remoteIdByTracker: const {},
                    sourceName: '',
                    mangaUrl: null,
                    client: client,
                  ),
                  providers: [provider],
                ),
              ),
              providerRecommendationsProvider(
                1,
                provider.key,
              ).overrideWith((ref) async => throw error),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: browse
                  ? RecommendsBrowseScreen(
                      mangaId: 1,
                      providerName: provider.key,
                    )
                  : const RecommendsScreen(mangaId: 1, mangaTitle: 'Example'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final message = switch (error) {
          RecommendationServiceUnavailable() =>
            'AniList is temporarily unavailable. Try again later.',
          RecommendationHttpException() || TimeoutException() =>
            "Couldn't load recommendations from AniList. Try again later.",
          _ => throw StateError('unexpected error $error'),
        };
        expect(find.text(message), findsOneWidget);
        expect(find.textContaining('WebView'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final mode in ['setup', 'section', 'grid']) {
    testWidgets('$mode loading explains what is being fetched', (tester) async {
      final client = http.Client();
      addTearDown(client.close);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            recommendationSetupProvider(1).overrideWith((ref) async {
              if (mode == 'setup') await Completer<void>().future;
              return (
                ctx: RecommendationContext(
                  title: 'Example',
                  remoteIdByTracker: const {},
                  sourceName: '',
                  mangaUrl: null,
                  client: client,
                ),
                providers: [provider],
              );
            }),
            providerRecommendationsProvider(1, provider.key).overrideWith((
              ref,
            ) async {
              await Completer<void>().future;
              return [];
            }),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: mode == 'grid'
                ? RecommendsBrowseScreen(mangaId: 1, providerName: provider.key)
                : const RecommendsScreen(mangaId: 1),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Fetching suggestions…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
