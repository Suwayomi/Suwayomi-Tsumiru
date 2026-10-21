import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/providers/anilist_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_provider.dart';

void main() {
  Future<List<Recommendation>> fetch(String body) {
    final client = MockClient((_) async => http.Response(body, 403));
    addTearDown(client.close);
    return const AnilistProvider().fetch(
      RecommendationContext(
        title: 'Example',
        remoteIdByTracker: const {'anilist': '1'},
        sourceName: '',
        mangaUrl: null,
        client: client,
      ),
    );
  }

  test('recognizes the confirmed AniList API outage response', () async {
    await expectLater(
      fetch(
        r'''{"errors":[{"message":"The AniList API has been temporarily disabled due to severe stability issues.","status":403,"locations":[{"line":1,"column":1}]}],"data":null}''',
      ),
      throwsA(isA<RecommendationServiceUnavailable>()),
    );
  });

  for (final body in [
    '<html>Forbidden</html>',
    '{invalid',
    '{"errors":[{"message":"Forbidden"}]}',
    '{"errors":"Forbidden"}',
    'null',
  ]) {
    test('other 403 responses retain their HTTP error: $body', () async {
      await expectLater(
        fetch(body),
        throwsA(
          isA<RecommendationHttpException>().having(
            (error) => error.statusCode,
            'statusCode',
            403,
          ),
        ),
      );
    });
  }
}
