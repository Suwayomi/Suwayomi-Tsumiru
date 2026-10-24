// Copyright (c) 2026 Contributors to the Suwayomi project

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/features/auth/data/simple_login_client.dart';

void main() {
  test('a successful login observes the 303 cookie, and the browser mode '
      'follows redirects', () async {
    bool? followRedirects;
    final mock = MockClient((request) async {
      if (request.url.path == '/api/graphql') {
        expect(request.headers['Cookie'], 'JSESSIONID=abc.123');
        expect(request.headers['Authorization'], isNull);
        return http.Response(
          '{"data":{"downloadStatus":{"__typename":"DownloadStatus"}}}',
          200,
        );
      }
      expect(request.url.toString(), 'https://server.test/login.html');
      expect(
        request.headers['Content-Type'],
        'application/x-www-form-urlencoded; charset=utf-8',
      );
      expect(request.bodyFields, {'user': 'aaron', 'pass': 'hunter2'});
      followRedirects = request.followRedirects;
      return http.Response(
        '',
        303,
        headers: {
          'location': '/',
          'set-cookie': 'JSESSIONID=abc.123; Path=/; HttpOnly',
        },
      );
    });

    final cookie = await SimpleLoginClient(httpClient: mock).login(
      serverBaseUrl: 'https://server.test',
      username: 'aaron',
      password: 'hunter2',
    );
    expect(cookie, 'JSESSIONID=abc.123');
    // Not following the 303 is what lets the cookie be observed.
    expect(followRedirects, isFalse);

    bool? browserFollows;
    final browser = MockClient((request) async {
      if (request.url.path == '/api/graphql') {
        expect(request.headers['Cookie'], isNull);
        return http.Response(
          '{"data":{"downloadStatus":{"__typename":"DownloadStatus"}}}',
          200,
        );
      }
      browserFollows = request.followRedirects;
      return http.Response('<html><div id="app"></div></html>', 200);
    });
    final browserCookie = await SimpleLoginClient(
      httpClient: browser,
      browserSession: true,
    ).login(serverBaseUrl: 'http://s', username: 'u', password: 'p');
    expect(browserCookie, kBrowserManagedSimpleSession);
    // `followRedirects: false` becomes fetch `redirect: 'error'` in a browser,
    // which fails the request as soon as the 303 arrives.
    expect(browserFollows, isTrue);
  });

  test(
    'a rejected login and an unexpected status are distinct failures',
    () async {
      final auth = MockClient(
        (request) async =>
            http.Response('<html>Invalid username or password</html>', 200),
      );
      await expectLater(
        SimpleLoginClient(httpClient: auth).login(
          serverBaseUrl: 'https://server.test',
          username: 'aaron',
          password: 'wrong',
        ),
        throwsA(isA<SimpleLoginAuthFailure>()),
      );

      final shape = MockClient((request) async => http.Response('', 500));
      await expectLater(
        SimpleLoginClient(httpClient: shape).login(
          serverBaseUrl: 'https://server.test',
          username: 'aaron',
          password: 'hunter2',
        ),
        throwsA(isA<SimpleLoginShapeFailure>()),
      );
    },
  );
}
