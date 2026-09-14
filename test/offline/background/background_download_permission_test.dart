import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/offline/data/background/background_chapter_fetch.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

import '../../helpers/fake_page_store.dart';

void main() {
  const record = BackgroundTokenRecord(
    gen: 0,
    authType: 'uiLogin',
    accessToken: 'token',
  );
  var refreshes = 0;
  TokenBroker broker() => TokenBroker(
    read: () async => record,
    write: (_) async {},
    refreshFn: (_) async {
      refreshes++;
      return (tokens: null, transient: false);
    },
  );
  BackgroundServerTarget target(
    http.Client client, {
    bool Function()? cancelled,
  }) => BackgroundServerTarget(
    serverBase: 'http://server',
    port: null,
    addPort: false,
    client: client,
    isCancelled: cancelled,
  );
  setUp(() => refreshes = 0);

  for (final payload in <Object?>[
    null,
    {},
    {'fetchChapterPages': null},
    {
      'fetchChapterPages': {'pages': null},
    },
    {
      'fetchChapterPages': {
        'pages': [1],
      },
    },
    {
      'fetchChapterPages': {'pages': []},
    },
  ]) {
    test('page resolution holds malformed response $payload', () async {
      const legacy = BackgroundTokenRecord(gen: 0, authType: 'none');
      final result = await resolveChapterPageUrls(
        target: target(
          MockClient(
            (_) async => http.Response(jsonEncode({'data': payload}), 200),
          ),
        ),
        record: () => legacy,
        broker: broker(),
        chapterId: 1,
      );
      final explicitEmpty =
          payload is Map &&
          payload['fetchChapterPages'] is Map &&
          (payload['fetchChapterPages'] as Map)['pages'] is List &&
          ((payload['fetchChapterPages'] as Map)['pages'] as List).isEmpty;
      expect(result, explicitEmpty ? isEmpty : isNull);
    });
  }

  for (final forbidden in [true, false]) {
    test(
      'GraphQL ${forbidden ? 'Forbidden' : 'Unauthorized'} precedes partial page data',
      () async {
        final result = postBackgroundGraphql(
          target: target(
            MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'data': {
                    'fetchChapterPages': {
                      'pages': ['/page'],
                    },
                  },
                  'errors': [
                    {
                      'message': forbidden
                          ? 'Exception while fetching data (/fetchChapterPages) : Forbidden'
                          : 'Unauthorized',
                    },
                  ],
                }),
                200,
              ),
            ),
          ),
          record: record,
          query: 'mutation Pages { fetchChapterPages { pages } }',
          variables: const {},
        );
        if (forbidden) {
          await expectLater(result, throwsA(isA<AccountPermissionDenied>()));
        } else {
          expect(await result, same(gqlAuthError));
        }
        expect(refreshes, 0);
      },
    );
  }

  for (final allowed in [true, false]) {
    test(
      'page resolution verifies fresh download permission $allowed before pages',
      () async {
        final queries = <String>[];
        final client = MockClient((request) async {
          final query = (jsonDecode(request.body) as Map)['query'] as String;
          queries.add(query);
          if (query.contains('AccountCapability')) {
            return http.Response('{"data":{"user":{"id":2}}}', 200);
          }
          if (query.contains('DownloadAccount')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'user': {
                    'id': 2,
                    'username': 'reader',
                    '__typename': 'UserType',
                    'roles': ['USER'],
                    'permissions': [if (allowed) 'DOWNLOAD_CHAPTERS'],
                  },
                },
              }),
              200,
            );
          }
          return http.Response(
            '{"data":{"fetchChapterPages":{"pages":["/page"]}}}',
            200,
          );
        });
        final result = resolveChapterPageUrls(
          target: target(client),
          record: () => record,
          broker: broker(),
          chapterId: 1,
        );
        if (allowed) {
          expect(await result, ['/page']);
        } else {
          await expectLater(result, throwsA(isA<AccountPermissionDenied>()));
        }
        expect(
          queries.where((query) => query.contains('GetChapterPages')).length,
          allowed ? 1 : 0,
        );
        expect(refreshes, 0);
      },
    );
  }

  for (final exactLegacy in [true, false]) {
    test(
      'legacy account detection requires the exact schema error $exactLegacy',
      () async {
        var requests = 0;
        final client = MockClient((_) async {
          requests++;
          return http.Response(
            jsonEncode({
              'errors': [
                {
                  'message': exactLegacy
                      ? 'Cannot query field "user" on type "Query".'
                      : 'Server error',
                  'extensions': {'code': 'GRAPHQL_VALIDATION_FAILED'},
                },
              ],
            }),
            200,
          );
        });
        expect(
          await verifyBackgroundDownloadAccess(
            target: target(client),
            record: () => record,
            broker: broker(),
          ),
          exactLegacy,
        );
        expect(requests, 1);
      },
    );
  }

  test(
    'a cancelled request cannot record a delayed permission denial',
    () async {
      var cancelled = false;
      final client = MockClient((_) async {
        cancelled = true;
        return http.Response('', 403);
      });
      expect(
        await postBackgroundGraphql(
          target: target(client, cancelled: () => cancelled),
          record: record,
          query: 'query User { user { id } }',
          variables: const {},
        ),
        same(gqlNetworkError),
      );
    },
  );

  test('HTTP client connection errors park without page retries', () async {
    var requests = 0;
    final engine = buildBackgroundEngine(
      store: FakePageStore(),
      target: target(
        MockClient((_) async {
          requests++;
          throw http.ClientException('Connection closed');
        }),
      ),
      record: () => record,
      broker: broker(),
    );
    final outcome = await engine.download(
      mangaId: 1,
      chapterId: 2,
      pages: [(index: 0, url: '/page')],
      isCancelled: () => false,
    );
    expect(outcome.offline, isTrue);
    expect(requests, 1);
    expect(refreshes, 0);
  });

  test('permission errors bypass page retries and token refresh', () async {
    var fetches = 0;
    var backoffs = 0;
    final engine = ChapterDownloadEngine(
      writePage: FakePageStore(),
      fetchPage: (_) async {
        fetches++;
        throw const AccountPermissionDenied(
          Enum$UserPermission.DOWNLOAD_CHAPTERS,
        );
      },
      refreshAuth: () async {
        refreshes++;
        return true;
      },
      backoff: (_) {
        backoffs++;
        return Duration.zero;
      },
    );
    final result = await engine.download(
      mangaId: 1,
      chapterId: 2,
      pages: [(index: 0, url: '/page')],
      isCancelled: () => false,
    );
    expect(result.error, isA<AccountPermissionDenied>());
    expect(fetches, 1);
    expect(backoffs, 0);
    expect(refreshes, 0);
  });
}
