// Copyright (c) 2026 Contributors to the Suwayomi project

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/features/auth/data/simple_login_client.dart';

void main() {
  group('SimpleLoginClient in a browser', () {
    test(
      'login follows redirects and verifies protected data before succeeding',
      () async {
        bool? followRedirects;
        final mock = MockClient((request) async {
          if (request.url.path == '/api/graphql') {
            expect(request.headers['Cookie'], isNull);
            return http.Response(
              '{"data":{"downloadStatus":{"__typename":"DownloadStatus"}}}',
              200,
            );
          }
          followRedirects = request.followRedirects;
          return http.Response('<html><div id="app"></div></html>', 200);
        });
        final cookie = await SimpleLoginClient(
          httpClient: mock,
          browserSession: true,
        ).login(serverBaseUrl: 'http://s', username: 'u', password: 'p');
        expect(cookie, kBrowserManagedSimpleSession);
        // `followRedirects: false` becomes fetch `redirect: 'error'` in a
        // browser, which fails the request as soon as the 303 arrives.
        expect(followRedirects, isTrue);
      },
    );
  });

  group('SimpleLoginClient', () {
    test('login returns cookie value on 303', () async {
      final mock = MockClient((request) async {
        expect(request.url.toString(), 'https://server.test/login.html');
        expect(
          request.headers['Content-Type'],
          'application/x-www-form-urlencoded; charset=utf-8',
        );
        expect(request.bodyFields, {'user': 'aaron', 'pass': 'hunter2'});
        return http.Response(
          '',
          303,
          headers: {
            'location': '/',
            'set-cookie': 'JSESSIONID=abc.123; Path=/; HttpOnly',
          },
        );
      });

      final client = SimpleLoginClient(httpClient: mock);
      final cookie = await client.login(
        serverBaseUrl: 'https://server.test',
        username: 'aaron',
        password: 'hunter2',
      );
      expect(cookie, 'JSESSIONID=abc.123');
    });

    test('login does not follow the 303 so the cookie is observed', () async {
      bool? followRedirects;
      final mock = MockClient((request) async {
        followRedirects = request.followRedirects;
        return http.Response(
          '',
          303,
          headers: {
            'set-cookie': 'JSESSIONID=abc; Path=/; HttpOnly',
            'location': '/',
          },
        );
      });
      final cookie = await SimpleLoginClient(
        httpClient: mock,
      ).login(serverBaseUrl: 'http://s', username: 'u', password: 'p');
      expect(followRedirects, isFalse);
      expect(cookie, 'JSESSIONID=abc');
    });

    test(
      'login throws SimpleLoginAuthFailure on 200 (re-rendered form)',
      () async {
        final mock = MockClient(
          (request) async =>
              http.Response('<html>Invalid username or password</html>', 200),
        );
        final client = SimpleLoginClient(httpClient: mock);

        expect(
          () => client.login(
            serverBaseUrl: 'https://server.test',
            username: 'aaron',
            password: 'wrong',
          ),
          throwsA(isA<SimpleLoginAuthFailure>()),
        );
      },
    );

    test('login throws SimpleLoginShapeFailure on unexpected status', () async {
      final mock = MockClient((request) async => http.Response('', 500));
      final client = SimpleLoginClient(httpClient: mock);

      expect(
        () => client.login(
          serverBaseUrl: 'https://server.test',
          username: 'aaron',
          password: 'hunter2',
        ),
        throwsA(isA<SimpleLoginShapeFailure>()),
      );
    });
  });
}
