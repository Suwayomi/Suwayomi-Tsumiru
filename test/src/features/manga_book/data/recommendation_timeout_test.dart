import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

class _HangingProvider extends RecommendationProvider {
  @override
  String get name => 'Hanging';
  @override
  String get category => 'test';
  @override
  Future<List<Recommendation>> fetch(RecommendationContext ctx) =>
      Completer<List<Recommendation>>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final cached in [false, true]) {
    test(
      'a hanging provider ${cached ? 'uses cached results' : 'settles with a timeout'}',
      () async {
        final provider = _HangingProvider();
        const saved = Recommendation(title: 'Saved', category: 'test');
        SharedPreferences.setMockInitialValues({
          'serverUrl': 'https://example.test',
          'serverPortToggle': false,
          if (cached)
            'recsCache:v2:${jsonEncode([
              ['server', 'https://example.test', 'none'],
              1,
              'Example',
              provider.key,
            ])}': jsonEncode([
              saved.toJson(),
            ]),
        });
        final prefs = await SharedPreferences.getInstance();
        final client = http.Client();
        addTearDown(client.close);
        fakeAsync((clock) {
          final container = ProviderContainer(
            retry: (_, _) => null,
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              authTypeKeyProvider.overrideWithValue(AuthType.none),
              currentServerAddressProvider.overrideWithValue(
                'https://example.test',
              ),
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
            ],
          );
          final individual = providerRecommendationsProvider(1, provider.key);
          container.listen(individual, (_, _) {});
          container.listen(mangaRecommendationsProvider(1), (_, _) {});
          clock.flushMicrotasks();
          clock.elapse(const Duration(seconds: 29));
          expect(container.read(individual).isLoading, isTrue);
          clock.elapse(const Duration(seconds: 1));
          clock.flushMicrotasks();
          if (cached) {
            expect(container.read(individual).value?.single.title, 'Saved');
            expect(
              container
                  .read(mangaRecommendationsProvider(1))
                  .value
                  ?.single
                  .title,
              'Saved',
            );
          } else {
            expect(container.read(individual).error, isA<TimeoutException>());
            expect(
              container.read(mangaRecommendationsProvider(1)).hasError,
              isTrue,
            );
          }
          container.dispose();
          clock.flushMicrotasks();
        });
      },
    );
  }
}
