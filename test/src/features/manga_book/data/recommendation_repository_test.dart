import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:tsumiru/src/features/manga_book/data/recommendations/providers/anilist_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/providers/comick_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/providers/mangadex_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/providers/mangaupdates_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/providers/myanimelist_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_repository.dart';

const _first = AnilistProvider();
const _second = MyAnimeListProvider();
const _one = Recommendation(title: 'One', category: 'test', sourceUrl: 'one');
const _two = Recommendation(title: 'Two', category: 'test', sourceUrl: 'two');
const _duplicate = Recommendation(
  title: 'Another title',
  category: 'test',
  sourceUrl: 'one',
);

void main() {
  late ProviderContainer container;
  late Completer<List<Recommendation>> first;
  late Completer<List<Recommendation>> second;

  setUp(() {
    first = Completer();
    second = Completer();
    final client = http.Client();
    addTearDown(client.close);
    container = ProviderContainer(
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
            providers: [_first, _second],
          ),
        ),
        providerRecommendationsProvider(
          1,
          _first.key,
        ).overrideWith((ref) => first.future),
        providerRecommendationsProvider(
          1,
          _second.key,
        ).overrideWith((ref) => second.future),
      ],
    );
    addTearDown(container.dispose);
    container.listen(mangaRecommendationsProvider(1), (_, _) {});
  });

  test(
    'shows completed suggestions while another provider is pending',
    () async {
      second.complete([_two]);
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      expect(container.read(mangaRecommendationsProvider(1)).value, [_two]);
    },
  );

  test('stays loading while all providers are pending', () async {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(container.read(mangaRecommendationsProvider(1)).isLoading, isTrue);
  });

  test('stays loading when only empty results have arrived', () async {
    first.complete([]);
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(container.read(mangaRecommendationsProvider(1)).isLoading, isTrue);
  });

  test('an empty provider beside a failed one produces empty data', () async {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    first.complete([]);
    second.completeError(StateError('Unavailable'));
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(container.read(mangaRecommendationsProvider(1)).value, isEmpty);
    expect(container.read(mangaRecommendationsProvider(1)).hasError, isFalse);
  });

  test('all providers failing reports an error', () async {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    first.completeError(StateError('First down'));
    second.completeError(StateError('Second down'));
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(container.read(mangaRecommendationsProvider(1)).hasError, isTrue);
  });

  test('settled successful empty providers produce an empty result', () async {
    first.complete([]);
    second.complete([]);
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(container.read(mangaRecommendationsProvider(1)).value, isEmpty);
    expect(container.read(mangaRecommendationsProvider(1)).hasError, isFalse);
  });

  test(
    'later results restore configured order and deduplicate URLs and titles',
    () async {
      const titleOnly = Recommendation(title: 'Title only', category: 'test');
      second.complete([_duplicate, _two, titleOnly]);
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      expect(container.read(mangaRecommendationsProvider(1)).value, [
        _duplicate,
        _two,
        titleOnly,
      ]);
      first.complete([_one, titleOnly]);
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      expect(container.read(mangaRecommendationsProvider(1)).value, [
        _one,
        titleOnly,
        _two,
      ]);
    },
  );

  test('waits for recommendation setup', () async {
    final setupContainer = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        recommendationSetupProvider(1).overrideWith((ref) async {
          await Completer<void>().future;
          return null;
        }),
      ],
    );
    addTearDown(setupContainer.dispose);
    setupContainer.listen(mangaRecommendationsProvider(1), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    await setupContainer.pump();
    expect(
      setupContainer.read(mangaRecommendationsProvider(1)).isLoading,
      isTrue,
    );
  });

  test('preserves setup errors', () async {
    final error = StateError('Setup failed');
    final setupContainer = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        recommendationSetupProvider(1).overrideWith((ref) async => throw error),
      ],
    );
    addTearDown(setupContainer.dispose);
    setupContainer.listen(mangaRecommendationsProvider(1), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    await setupContainer.pump();
    expect(
      setupContainer.read(mangaRecommendationsProvider(1)).error,
      same(error),
    );
  });

  test('web keeps only AniList; native keeps every applicable provider', () {
    final client = http.Client();
    addTearDown(client.close);
    final ctx = RecommendationContext(
      title: 'Example',
      remoteIdByTracker: const {},
      sourceName: 'Comick MangaDex',
      mangaUrl: '/comic/abc#',
      client: client,
    );
    const all = [
      AnilistProvider(),
      MangaUpdatesCommunityProvider(),
      MangaUpdatesSimilarProvider(),
      MyAnimeListProvider(),
      MangaDexProvider(),
      ComickProvider(),
    ];
    final web = [
      for (final p in all)
        if (appliesOnPlatform(p, ctx, isWeb: true)) p.key,
    ];
    expect(web, [const AnilistProvider().key]);
    final native = [
      for (final p in all)
        if (appliesOnPlatform(p, ctx, isWeb: false)) p.key,
    ];
    expect(
      native,
      containsAll([
        const AnilistProvider().key,
        const MangaUpdatesCommunityProvider().key,
        const MangaUpdatesSimilarProvider().key,
        const MangaDexProvider().key,
        const ComickProvider().key,
      ]),
    );
  });

  test('missing setup produces an empty result', () async {
    final setupContainer = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        recommendationSetupProvider(1).overrideWith((ref) async => null),
      ],
    );
    addTearDown(setupContainer.dispose);
    setupContainer.listen(mangaRecommendationsProvider(1), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    await setupContainer.pump();
    expect(setupContainer.read(mangaRecommendationsProvider(1)).value, isEmpty);
  });
}
