// Copyright (c) 2026 Contributors to the Suwayomi project

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/features/auth/data/simple_login_client.dart';

void main() {
  group('SimpleLoginClient', () {
    test('login returns cookie value on 303', () async {
      final mock = MockClient((request) async {
        expect(request.url.toString(), 'https://server.test/login.html');
        expect(request.headers['Content-Type'],
            'application/x-www-form-urlencoded; charset=utf-8');
        expect(request.bodyFields, {'user': 'aaron', 'pass': 'hunter2'});
        return http.Response(
          '',
          303,
          headers: {
            'location': '/',
            'set-cookie':
                'JSESSIONID=abc.123; Path=/; HttpOnly',
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
        return http.Response('', 303, headers: {
          'set-cookie': 'JSESSIONID=abc; Path=/; HttpOnly',
          'location': '/',
        });
      });
      final cookie = await SimpleLoginClient(httpClient: mock).login(
        serverBaseUrl: 'http://s',
        username: 'u',
        password: 'p',
      );
      expect(followRedirects, isFalse);
      expect(cookie, 'JSESSIONID=abc');
    });

    test('login throws SimpleLoginAuthFailure on 200 (re-rendered form)',
        () async {
      final mock = MockClient((request) async => http.Response(
            '<html>Invalid username or password</html>',
            200,
          ));
      final client = SimpleLoginClient(httpClient: mock);

      expect(
        () => client.login(
          serverBaseUrl: 'https://server.test',
          username: 'aaron',
          password: 'wrong',
        ),
        throwsA(isA<SimpleLoginAuthFailure>()),
      );
    });

    test('login throws SimpleLoginShapeFailure on unexpected status',
        () async {
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

    test('login throws SimpleLoginShapeFailure when 303 has no Set-Cookie',
        () async {
      final mock = MockClient((request) async => http.Response(
            '',
            303,
            headers: {'location': '/'},
          ));
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

    test('login sends extraHeaders and does not overwrite auth headers',
        () async {
      Map<String, String>? capturedHeaders;
      final mock = MockClient((request) async {
        capturedHeaders = request.headers;
        return http.Response('', 303, headers: {
          'set-cookie': 'JSESSIONID=xyz; Path=/; HttpOnly',
          'location': '/',
        });
      });
      final client = SimpleLoginClient(httpClient: mock);
      final cookie = await client.login(
        serverBaseUrl: 'https://server.test',
        username: 'aaron',
        password: 'hunter2',
        extraHeaders: {
          'CF-Access-Client-Id': 'client-id-123',
          'Authorization': 'forbidden',
          'cookie': 'forbidden-cookie',
        },
      );
      expect(cookie, 'JSESSIONID=xyz');
      expect(capturedHeaders?['CF-Access-Client-Id'], 'client-id-123');
      expect(capturedHeaders?['Authorization'], isNull);
      expect(capturedHeaders?['cookie'], isNull);
    });
  });
}
