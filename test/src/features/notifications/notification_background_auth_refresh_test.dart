import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';

void main() {
  group('isGraphqlAuthError', () {
    test('detects an in-band 401 via extensions.http.status', () {
      expect(
        isGraphqlAuthError([
          {
            'message': 'Access denied',
            'extensions': {
              'http': {'status': 401},
            },
          },
        ]),
        isTrue,
      );
    });

    test('detects an "unauthorized" message with no extensions', () {
      expect(
        isGraphqlAuthError([
          {'message': 'Unauthorized'},
        ]),
        isTrue,
      );
    });

    test('a non-auth error is not treated as auth', () {
      expect(
        isGraphqlAuthError([
          {
            'message': 'Some field error',
            'extensions': {
              'http': {'status': 500},
            },
          },
        ]),
        isFalse,
      );
    });

    test('null / empty is not auth', () {
      expect(isGraphqlAuthError(null), isFalse);
      expect(isGraphqlAuthError(const []), isFalse);
    });
  });

  test(
    'a uiLogin 200-with-errors auth response refreshes the token and retries',
    () async {
      // The server reports an expired access token as HTTP 200 carrying a
      // GraphQL 401, not a real HTTP 401. The client must still route it to the
      // broker refresh and retry with the fresh token — the background overnight
      // fix.
      var stored = const BackgroundTokenRecord(
        gen: 0,
        authType: 'uiLogin',
        endpoint: 'e',
        accessToken: 'expired',
        refreshToken: 'rt',
      );
      var refreshCalls = 0;
      final broker = TokenBroker(
        read: () async => stored,
        write: (r) async => stored = r,
        refreshFn: (rt) async {
          refreshCalls++;
          return (tokens: (access: 'fresh', refresh: rt), transient: false);
        },
      );

      var queryPosts = 0;
      final mock = MockClient((req) async {
        queryPosts++;
        final auth = req.headers['Authorization'] ?? req.headers['authorization'];
        if (auth == 'Bearer fresh') {
          return http.Response(
            jsonEncode({
              'data': {
                'chapters': {
                  'pageInfo': {'hasNextPage': false, 'endCursor': null},
                  'nodes': const [],
                },
              },
            }),
            200,
          );
        }
        // Expired token → HTTP 200 with an in-band GraphQL 401.
        return http.Response(
          jsonEncode({
            'errors': [
              {
                'message': 'Access denied',
                'extensions': {
                  'http': {'status': 401},
                },
              },
            ],
            'data': null,
          }),
          200,
        );
      });

      final client = NotificationBackgroundClient(
        endpoint: const NotificationEndpoint(
          baseUrl: 'http://server.test',
          addPort: false,
        ),
        record: stored,
        broker: broker,
        httpClient: mock,
      );

      final page = await client.fetchNewChaptersPage(fetchedAtGte: '0');

      expect(page, isNotNull, reason: 'the retry after refresh should succeed');
      expect(refreshCalls, 1, reason: 'the in-band 401 must trigger one refresh');
      expect(queryPosts, 2, reason: 'one failing call + one retry');
      expect(client.currentRecord().accessToken, 'fresh');
    },
  );

  test('a token known to be expired is refreshed before the first request, '
      'so the worker never collects the 401', () async {
    String part(Object json) =>
        base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
    final expired =
        '${part({'alg': 'HS256'})}.'
        '${part({'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 10800})}'
        '.sig';
    var stored = BackgroundTokenRecord(
      gen: 0,
      authType: 'uiLogin',
      endpoint: 'e',
      accessToken: expired,
      refreshToken: 'rt',
    );
    var refreshCalls = 0;
    final broker = TokenBroker(
      read: () async => stored,
      write: (r) async => stored = r,
      refreshFn: (rt) async {
        refreshCalls++;
        return (tokens: (access: 'fresh', refresh: rt), transient: false);
      },
    );
    final auths = <String?>[];
    final client = NotificationBackgroundClient(
      endpoint: const NotificationEndpoint(
        baseUrl: 'http://server.test',
        addPort: false,
      ),
      record: stored,
      broker: broker,
      httpClient: MockClient((req) async {
        auths.add(req.headers['Authorization']);
        return http.Response(
          jsonEncode({
            'data': {
              'chapters': {
                'pageInfo': {'hasNextPage': false, 'endCursor': null},
                'nodes': const [],
              },
            },
          }),
          200,
        );
      }),
    );

    expect(await client.fetchNewChaptersPage(fetchedAtGte: '0'), isNotNull);
    expect(refreshCalls, 1);
    expect(auths, ['Bearer fresh']);
    expect(client.currentRecord().accessToken, 'fresh');
  });

  test('a refresh made through the shared broker reaches the client', () async {
    var stored = const BackgroundTokenRecord(
      gen: 0,
      authType: 'uiLogin',
      endpoint: 'e',
      accessToken: 'old',
      refreshToken: 'rt',
    );
    final broker = TokenBroker(
      read: () async => stored,
      write: (r) async => stored = r,
      refreshFn: (rt) async =>
          (tokens: (access: 'fresh', refresh: rt), transient: false),
    );
    final client = NotificationBackgroundClient(
      endpoint: const NotificationEndpoint(
        baseUrl: 'http://server.test',
        addPort: false,
      ),
      record: stored,
      broker: broker,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    // What the catch-up executor does on its own 401.
    await broker.resolveAfter401('old');
    expect(client.currentRecord().accessToken, 'fresh');
  });
}
