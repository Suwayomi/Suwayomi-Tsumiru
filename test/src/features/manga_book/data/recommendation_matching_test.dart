import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/providers/mangaupdates_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/providers/myanimelist_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_provider.dart';

RecommendationContext _context(
  http.Client client,
  String title, {
  Map<String, String> ids = const {},
}) => RecommendationContext(
  title: title,
  remoteIdByTracker: ids,
  sourceName: '',
  mangaUrl: null,
  client: client,
);

void main() {
  const mu = MangaUpdatesCommunityProvider();
  const mal = MyAnimeListProvider();
  const muDetails =
      '{"recommendations":[{"series_name":"Matched recommendation","series_url":"https://example.test/rec"}]}';
  const malDetails =
      '{"recommendations":[{"node":{"id":9,"title":"Matched recommendation"}}]}';

  test(
    'MangaUpdates rejects the observed unrelated Pepper&Carrot search hits',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          return http.Response(
            r'''{"results":[{"record":{"title":"Shinigami wa Korosenai","series_id":62247905207},"hit_title":"Reaper Cannot Kill"},{"record":{"title":"Pepper","series_id":50296296953},"hit_title":"Pepper"},{"record":{"title":"Mahou Shoujo Carrot Carrot","series_id":39254616246},"hit_title":"Mahou Shoujo Carrot Carrot"}]}''',
            200,
          );
        }
        return http.Response(muDetails, 200);
      });
      addTearDown(client.close);
      expect(
        await mu.fetchBySearch(_context(client, 'Pepper&Carrot')),
        isEmpty,
      );
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
    },
  );

  test('MangaUpdates selects a later normalized title match', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'POST') {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'record': {'title': 'Unrelated', 'series_id': 1},
              },
              {
                'record': {'title': 'ＰＥＰＰＥＲ — Carrot!', 'series_id': 2},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(muDetails, 200);
    });
    addTearDown(client.close);
    final result = await mu.fetchBySearch(_context(client, 'Pepper&Carrot'));
    expect(result.single.title, 'Matched recommendation');
    expect(requests.last.url.path, '/v1/series/2');
    expect(requests, hasLength(2));
  });

  test('MangaUpdates keeps an explicitly linked tracker ID', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(muDetails, 200);
    });
    addTearDown(client.close);
    await mu.fetch(
      _context(client, 'Other local title', ids: {'mangaupdates': '42'}),
    );
    expect(requests.single.url.path, '/v1/series/42');
    expect(requests.single.method, 'GET');
  });

  for (final title in ['', '!!!']) {
    test(
      'MangaUpdates does not match an empty normalized title: $title',
      () async {
        var detailCalls = 0;
        final client = MockClient((request) async {
          if (request.method == 'GET') {
            detailCalls++;
            return http.Response(muDetails, 200);
          }
          return http.Response(
            '{"results":[{"record":{"title":"---","series_id":1}}]}',
            200,
          );
        });
        addTearDown(client.close);
        expect(await mu.fetchBySearch(_context(client, title)), isEmpty);
        expect(detailCalls, 0);
      },
    );
  }

  test('MangaUpdates handles an empty search result', () async {
    final client = MockClient(
      (_) async => http.Response('{"results":[]}', 200),
    );
    addTearDown(client.close);
    expect(await mu.fetchBySearch(_context(client, 'Pepper&Carrot')), isEmpty);
  });

  test(
    'MyAnimeList rejects an unrelated first result without requesting details',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          request.url.path == '/v2/manga'
              ? '{"data":[{"node":{"id":1,"title":"Unrelated"}}]}'
              : malDetails,
          200,
        );
      });
      addTearDown(client.close);
      expect(
        await mal.fetchBySearch(_context(client, 'Pepper&Carrot')),
        isEmpty,
      );
      expect(requests, hasLength(1));
      expect(requests.single.url.queryParameters['limit'], '10');
      expect(
        requests.single.url.queryParameters['fields'],
        'alternative_titles',
      );
    },
  );

  test('MyAnimeList accepts a normalized title match', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        request.url.path == '/v2/manga'
            ? '{"data":[{"node":{"id":2,"title":"PEPPER - CARROT!"}}]}'
            : malDetails,
        200,
      );
    });
    addTearDown(client.close);
    expect(
      (await mal.fetchBySearch(_context(client, 'Pepper&Carrot'))).single.title,
      'Matched recommendation',
    );
    expect(requests.last.url.path, '/v2/manga/2');
  });

  test('MyAnimeList does not match a blank normalized title', () async {
    var detailCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path != '/v2/manga') {
        detailCalls++;
        return http.Response(malDetails, 200);
      }
      return http.Response('{"data":[{"node":{"id":1,"title":"---"}}]}', 200);
    });
    addTearDown(client.close);
    expect(await mal.fetchBySearch(_context(client, '!!!')), isEmpty);
    expect(detailCalls, 0);
  });

  test('MyAnimeList keeps an explicitly linked tracker ID', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(malDetails, 200);
    });
    addTearDown(client.close);
    await mal.fetch(
      _context(client, 'Other local title', ids: {'myanimelist': '42'}),
    );
    expect(requests.single.url.path, '/v2/manga/42');
  });
  for (final example in [
    (query: 'Only I Level Up', canonical: 'Solo Leveling', id: 15180124327),
    (
      query: 'Star-Fostered Swordmaster',
      canonical: 'The Stellar Swordmaster',
      id: 27558584427,
    ),
    (
      query: 'Star-Embracing Swordmaster',
      canonical: 'The Stellar Swordmaster',
      id: 27558584427,
    ),
  ]) {
    test(
      'MangaUpdates accepts verified hit-title alias ${example.query}',
      () async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          return http.Response(
            request.method == 'POST'
                ? jsonEncode({
                    'results': [
                      {
                        'record': {
                          'title': example.canonical,
                          'series_id': example.id,
                        },
                        'hit_title': example.query,
                      },
                    ],
                  })
                : muDetails,
            200,
          );
        });
        addTearDown(client.close);
        expect(
          (await mu.fetchBySearch(
            _context(client, example.query),
          )).single.title,
          'Matched recommendation',
        );
        expect(requests.last.url.path, '/v1/series/${example.id}');
        expect(requests, hasLength(2));
      },
    );
  }

  test(
    'MangaUpdates accepts the Count family alias without matching its novel',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          request.method == 'POST'
              ? jsonEncode({
                  'results': [
                    {
                      'record': {
                        'title': "Lout of Count's Family",
                        'series_id': 28433049110,
                      },
                      'hit_title': "Trash of the Count's Family",
                    },
                    {
                      'record': {
                        'title': "Lout of Count's Family (Novel)",
                        'series_id': 63936978061,
                      },
                      'hit_title': "Trash of the Count's Family (Novel)",
                    },
                  ],
                })
              : muDetails,
          200,
        );
      });
      addTearDown(client.close);
      expect(
        (await mu.fetchBySearch(
          _context(client, "Trash of the Count's Family"),
        )).single.title,
        'Matched recommendation',
      );
      expect(requests.last.url.path, '/v1/series/28433049110');
      expect(requests, hasLength(2));
    },
  );

  for (final duplicateId in [false, true]) {
    test(
      'MangaUpdates ${duplicateId ? 'deduplicates matching IDs' : 'rejects ambiguous matching IDs'}',
      () async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          return http.Response(
            request.method == 'POST'
                ? jsonEncode({
                    'results': [
                      {
                        'record': {'title': 'Solo Leveling', 'series_id': 1},
                        'hit_title': 'Only I Level Up',
                      },
                      {
                        'record': {
                          'title': 'Only I Level Up',
                          'series_id': duplicateId ? 1 : 2,
                        },
                      },
                    ],
                  })
                : muDetails,
            200,
          );
        });
        addTearDown(client.close);
        final result = await mu.fetchBySearch(
          _context(client, 'Only I Level Up'),
        );
        expect(result, duplicateId ? hasLength(1) : isEmpty);
        expect(requests, hasLength(duplicateId ? 2 : 1));
      },
    );
  }

  for (final alternatives in [
    {
      'synonyms': ['Only I Level Up'],
    },
    {'en': 'Only I Level Up'},
    {'ja': 'Only I Level Up'},
  ]) {
    test(
      'MyAnimeList accepts a later known alias from ${alternatives.keys.single}',
      () async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          return http.Response(
            request.url.path == '/v2/manga'
                ? jsonEncode({
                    'data': [
                      {
                        'node': {'id': 1, 'title': 'Unrelated'},
                      },
                      {
                        'node': {
                          'id': 2,
                          'title': 'Solo Leveling',
                          'alternative_titles': alternatives,
                        },
                      },
                    ],
                  })
                : malDetails,
            200,
          );
        });
        addTearDown(client.close);
        expect(
          (await mal.fetchBySearch(
            _context(client, 'Only I Level Up'),
          )).single.title,
          'Matched recommendation',
        );
        expect(requests.last.url.path, '/v2/manga/2');
        expect(requests.first.url.queryParameters, {
          'q': 'Only I Level Up',
          'limit': '10',
          'fields': 'alternative_titles',
        });
        expect(requests, hasLength(2));
      },
    );
  }

  for (final alternatives in [
    null,
    <String, Object?>{},
    {'synonyms': null, 'en': null, 'ja': null},
  ]) {
    test(
      'MyAnimeList handles absent or empty alternative-title values: $alternatives',
      () async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          return http.Response(
            request.url.path == '/v2/manga'
                ? jsonEncode({
                    'data': [
                      {
                        'node': {
                          'id': 1,
                          'title': 'Unrelated',
                          'alternative_titles': alternatives,
                        },
                      },
                      {
                        'node': {
                          'id': 2,
                          'title': 'Only I Level Up',
                          'alternative_titles': alternatives,
                        },
                      },
                    ],
                  })
                : malDetails,
            200,
          );
        });
        addTearDown(client.close);
        expect(
          (await mal.fetchBySearch(
            _context(client, 'Only I Level Up'),
          )).single.title,
          'Matched recommendation',
        );
        expect(requests.last.url.path, '/v2/manga/2');
      },
    );
  }

  for (final duplicateId in [false, true]) {
    test(
      'MyAnimeList ${duplicateId ? 'deduplicates matching IDs' : 'rejects ambiguous matching IDs'}',
      () async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          return http.Response(
            request.url.path == '/v2/manga'
                ? jsonEncode({
                    'data': [
                      {
                        'node': {'id': 1, 'title': 'Only I Level Up'},
                      },
                      {
                        'node': {
                          'id': duplicateId ? 1 : 2,
                          'title': 'Solo Leveling',
                          'alternative_titles': {
                            'synonyms': ['Only I Level Up'],
                          },
                        },
                      },
                    ],
                  })
                : malDetails,
            200,
          );
        });
        addTearDown(client.close);
        final result = await mal.fetchBySearch(
          _context(client, 'Only I Level Up'),
        );
        expect(result, duplicateId ? hasLength(1) : isEmpty);
        expect(requests, hasLength(duplicateId ? 2 : 1));
      },
    );
  }
}
