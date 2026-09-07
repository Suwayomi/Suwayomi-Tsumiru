import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/utils/network/timeout_http_client.dart';

http.Request _graphqlRequest(String query) =>
    http.Request('POST', Uri.parse('http://x/api/graphql'))
      ..body = jsonEncode({'query': query, 'variables': <String, dynamic>{}});

void main() {
  group('TimeoutHttpClient', () {
    test('sends a MultipartRequest without throwing (backup/extension upload)',
        () async {
      final mock = MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream.value(<int>[]),
          200,
          request: request,
        );
      });
      final client = TimeoutHttpClient(
        const Duration(seconds: 5),
        retries: 2,
        inner: mock,
      );

      final req = http.MultipartRequest('POST', Uri.parse('http://x/api'))
        ..files.add(http.MultipartFile.fromString('backup', 'data'));

      final res = await client.send(req);
      expect(res.statusCode, 200);
    });

    test('retries a plain http.Request on timeout', () async {
      var attempts = 0;
      final mock = MockClient.streaming((request, bodyStream) async {
        attempts++;
        if (attempts == 1) throw TimeoutException('slow');
        return http.StreamedResponse(Stream.value(<int>[]), 200,
            request: request);
      });
      final client = TimeoutHttpClient(
        const Duration(seconds: 5),
        retries: 2,
        retryDelay: Duration.zero,
        inner: mock,
      );

      final res =
          await client.send(http.Request('GET', Uri.parse('http://x/api')));
      expect(res.statusCode, 200);
      expect(attempts, 2);
    });

    test('retries a safe request once at a replacement endpoint', () async {
      final requestedUris = <Uri>[];
      final mock = MockClient.streaming((request, bodyStream) async {
        requestedUris.add(request.url);
        if (request.url.host == 'lan') throw http.ClientException('offline');
        return http.StreamedResponse(Stream.value(<int>[]), 200,
            request: request);
      });
      final client = TimeoutHttpClient(
        const Duration(seconds: 5),
        inner: mock,
        onConnectionFailure: (request) async =>
            Uri.parse('http://remote/api/graphql'),
      );

      final request = http.Request('POST', Uri.parse('http://lan/api/graphql'))
        ..body = jsonEncode(<String, dynamic>{
          'query': 'query GetLibrary { id }',
          'variables': <String, dynamic>{},
        });
      final response = await client.send(request);

      expect(response.statusCode, 200);
      expect(requestedUris, <Uri>[
        Uri.parse('http://lan/api/graphql'),
        Uri.parse('http://remote/api/graphql'),
      ]);
    });

    test('does not retry a multipart body on timeout (single-use stream)',
        () async {
      var attempts = 0;
      final mock = MockClient.streaming((request, bodyStream) async {
        attempts++;
        await bodyStream.drain<void>();
        throw TimeoutException('slow');
      });
      final client = TimeoutHttpClient(
        const Duration(seconds: 5),
        retries: 2,
        retryDelay: Duration.zero,
        inner: mock,
      );

      final req = http.MultipartRequest('POST', Uri.parse('http://x/api'))
        ..fields['k'] = 'v';

      await expectLater(client.send(req), throwsA(isA<TimeoutException>()));
      expect(attempts, 1);
    });

    test('does not retry a GraphQL mutation on timeout (not idempotent)',
        () async {
      var attempts = 0;
      final mock = MockClient.streaming((request, bodyStream) async {
        attempts++;
        await bodyStream.drain<void>();
        throw TimeoutException('slow');
      });
      final client = TimeoutHttpClient(
        const Duration(seconds: 5),
        retries: 2,
        retryDelay: Duration.zero,
        inner: mock,
      );

      final req = _graphqlRequest('mutation UpdateChapter { id }');

      await expectLater(client.send(req), throwsA(isA<TimeoutException>()));
      expect(attempts, 1,
          reason: 'a mutation may already have been applied server-side; '
              'retrying risks silently doubling its effect');
    });

    test('still retries a GraphQL query on timeout', () async {
      var attempts = 0;
      final mock = MockClient.streaming((request, bodyStream) async {
        attempts++;
        if (attempts == 1) throw TimeoutException('slow');
        return http.StreamedResponse(Stream.value(<int>[]), 200,
            request: request);
      });
      final client = TimeoutHttpClient(
        const Duration(seconds: 5),
        retries: 2,
        retryDelay: Duration.zero,
        inner: mock,
      );

      final res =
          await client.send(_graphqlRequest('query GetLibrary { id }'));
      expect(res.statusCode, 200);
      expect(attempts, 2);
    });

    test('still retries an anonymous/shorthand GraphQL query on timeout',
        () async {
      var attempts = 0;
      final mock = MockClient.streaming((request, bodyStream) async {
        attempts++;
        if (attempts == 1) throw TimeoutException('slow');
        return http.StreamedResponse(Stream.value(<int>[]), 200,
            request: request);
      });
      final client = TimeoutHttpClient(
        const Duration(seconds: 5),
        retries: 2,
        retryDelay: Duration.zero,
        inner: mock,
      );

      final res = await client.send(_graphqlRequest('{ library { id } }'));
      expect(res.statusCode, 200);
      expect(attempts, 2);
    });

    test(
      'late failure from an old session cannot resolve a new endpoint',
      () async {
        var current = true;
        var sends = 0;
        var resolutions = 0;
        final started = Completer<void>();
        final failure = Completer<http.StreamedResponse>();
        final client = TimeoutHttpClient(
          const Duration(seconds: 5),
          isCurrentSession: () => current,
          inner: MockClient.streaming((request, body) {
            sends++;
            started.complete();
            return failure.future;
          }),
          onConnectionFailure: (_) async {
            resolutions++;
            return Uri.parse('http://new/api/graphql');
          },
        );
        final pending = expectLater(
          client.send(_graphqlRequest('{ library { id } }')),
          throwsStateError,
        );
        await started.future;
        current = false;
        failure.completeError(http.ClientException('old connection failed'));
        await pending;
        expect(sends, 1);
        expect(resolutions, 0);
      },
    );

    test('a switch during endpoint resolution cancels the retry', () async {
      var current = true;
      var sends = 0;
      final resolving = Completer<void>();
      final endpoint = Completer<Uri?>();
      final client = TimeoutHttpClient(
        const Duration(seconds: 5),
        isCurrentSession: () => current,
        inner: MockClient.streaming((request, body) async {
          sends++;
          if (sends == 1) throw http.ClientException('offline');
          return http.StreamedResponse(const Stream.empty(), 200);
        }),
        onConnectionFailure: (_) {
          resolving.complete();
          return endpoint.future;
        },
      );
      final pending = expectLater(
        client.send(_graphqlRequest('{ library { id } }')),
        throwsStateError,
      );
      await resolving.future;
      current = false;
      endpoint.complete(Uri.parse('http://new/api/graphql'));
      await pending;
      expect(sends, 1);
    });

    test('a switch during the retry delay prevents another send', () {
      fakeAsync((clock) {
        var current = true;
        var sends = 0;
        Object? error;
        final client = TimeoutHttpClient(
          const Duration(seconds: 5),
          retries: 1,
          retryDelay: const Duration(seconds: 1),
          isCurrentSession: () => current,
          inner: MockClient.streaming((request, body) async {
            sends++;
            if (sends == 1) throw TimeoutException('slow');
            return http.StreamedResponse(const Stream.empty(), 200);
          }),
        );
        client
            .send(_graphqlRequest('{ library { id } }'))
            .then<void>(
              (_) {},
              onError: (Object failure) {
                error = failure;
              },
            );
        clock.flushMicrotasks();
        expect(sends, 1);
        current = false;
        clock.elapse(const Duration(seconds: 1));
        expect(sends, 1);
        expect(error, isStateError);
      });
    });

    test('same-session endpoint failover remains available', () async {
      final urls = <Uri>[];
      final client = TimeoutHttpClient(
        const Duration(seconds: 5),
        isCurrentSession: () => true,
        inner: MockClient.streaming((request, body) async {
          urls.add(request.url);
          if (urls.length == 1) throw http.ClientException('offline');
          return http.StreamedResponse(const Stream.empty(), 200);
        }),
        onConnectionFailure: (_) async => Uri.parse('http://new/api/graphql'),
      );
      expect(
        (await client.send(_graphqlRequest('{ library { id } }'))).statusCode,
        200,
      );
      expect(urls.map((uri) => uri.host), ['x', 'new']);
    });
  });
}
