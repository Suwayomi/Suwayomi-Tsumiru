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
    test('multipart uploads send, but a multipart timeout and a mutation '
        'timeout are not retried', () async {
      // A multipart upload goes through untouched.
      var multipartSends = 0;
      final ok = TimeoutHttpClient(
        const Duration(seconds: 5),
        retries: 2,
        inner: MockClient.streaming((request, bodyStream) async {
          multipartSends++;
          await bodyStream.drain<void>();
          return http.StreamedResponse(
            Stream.value(<int>[]),
            200,
            request: request,
          );
        }),
      );
      final upload = http.MultipartRequest('POST', Uri.parse('http://x/api'))
        ..files.add(http.MultipartFile.fromString('backup', 'data'));
      expect((await ok.send(upload)).statusCode, 200);
      expect(multipartSends, 1);

      // A multipart timeout never retries (single-use stream).
      var multipartAttempts = 0;
      final timeout = MockClient.streaming((request, bodyStream) async {
        multipartAttempts++;
        await bodyStream.drain<void>();
        throw TimeoutException('slow');
      });
      final multipartClient = TimeoutHttpClient(
        const Duration(seconds: 5),
        retries: 2,
        retryDelay: Duration.zero,
        inner: timeout,
      );
      final multipart = http.MultipartRequest('POST', Uri.parse('http://x/api'))
        ..fields['k'] = 'v';
      await expectLater(
        multipartClient.send(multipart),
        throwsA(isA<TimeoutException>()),
      );
      expect(multipartAttempts, 1);

      // A GraphQL mutation is not idempotent, so it never retries.
      var mutationAttempts = 0;
      final mutationClient = TimeoutHttpClient(
        const Duration(seconds: 5),
        retries: 2,
        retryDelay: Duration.zero,
        inner: MockClient.streaming((request, bodyStream) async {
          mutationAttempts++;
          await bodyStream.drain<void>();
          throw TimeoutException('slow');
        }),
      );
      await expectLater(
        mutationClient.send(_graphqlRequest('mutation UpdateChapter { id }')),
        throwsA(isA<TimeoutException>()),
      );
      expect(
        mutationAttempts,
        1,
        reason:
            'a mutation may already have been applied server-side; '
            'retrying risks silently doubling its effect',
      );
    });

    test(
      'retries a plain safe request and a GraphQL query on timeout',
      () async {
        var plainAttempts = 0;
        final plainClient = TimeoutHttpClient(
          const Duration(seconds: 5),
          retries: 2,
          retryDelay: Duration.zero,
          inner: MockClient.streaming((request, bodyStream) async {
            plainAttempts++;
            if (plainAttempts == 1) throw TimeoutException('slow');
            return http.StreamedResponse(
              Stream.value(<int>[]),
              200,
              request: request,
            );
          }),
        );
        final plain = await plainClient.send(
          http.Request('GET', Uri.parse('http://x/api')),
        );
        expect(plain.statusCode, 200);
        expect(plainAttempts, 2);

        // Named and anonymous/shorthand queries both retry.
        for (final query in ['query GetLibrary { id }', '{ library { id } }']) {
          var queryAttempts = 0;
          final client = TimeoutHttpClient(
            const Duration(seconds: 5),
            retries: 2,
            retryDelay: Duration.zero,
            inner: MockClient.streaming((request, bodyStream) async {
              queryAttempts++;
              if (queryAttempts == 1) throw TimeoutException('slow');
              return http.StreamedResponse(
                Stream.value(<int>[]),
                200,
                request: request,
              );
            }),
          );
          final res = await client.send(_graphqlRequest(query));
          expect(res.statusCode, 200, reason: query);
          expect(queryAttempts, 2, reason: query);
        }
      },
    );

    test(
      'a connection failure fails over to the replacement endpoint',
      () async {
        final requestedUris = <Uri>[];
        final client = TimeoutHttpClient(
          const Duration(seconds: 5),
          inner: MockClient.streaming((request, bodyStream) async {
            requestedUris.add(request.url);
            if (request.url.host == 'lan') {
              throw http.ClientException('offline');
            }
            return http.StreamedResponse(
              Stream.value(<int>[]),
              200,
              request: request,
            );
          }),
          onConnectionFailure: (request) async =>
              Uri.parse('http://remote/api/graphql'),
        );
        final request =
            http.Request('POST', Uri.parse('http://lan/api/graphql'))
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

        // A same-session failover stays available.
        final urls = <Uri>[];
        final sameSession = TimeoutHttpClient(
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
          (await sameSession.send(
            _graphqlRequest('{ library { id } }'),
          )).statusCode,
          200,
        );
        expect(urls.map((uri) => uri.host), ['x', 'new']);
      },
    );

    test('a session switch cancels pending retries', () async {
      // A late failure from an old session cannot resolve a new endpoint.
      var current = true;
      var sends = 0;
      var resolutions = 0;
      final started = Completer<void>();
      final failure = Completer<http.StreamedResponse>();
      final lateClient = TimeoutHttpClient(
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
      final late = expectLater(
        lateClient.send(_graphqlRequest('{ library { id } }')),
        throwsStateError,
      );
      await started.future;
      current = false;
      failure.completeError(http.ClientException('old connection failed'));
      await late;
      expect(sends, 1);
      expect(resolutions, 0);

      // A switch during endpoint resolution cancels the retry.
      var resolvingCurrent = true;
      var resolvingSends = 0;
      final resolving = Completer<void>();
      final endpoint = Completer<Uri?>();
      final resolvingClient = TimeoutHttpClient(
        const Duration(seconds: 5),
        isCurrentSession: () => resolvingCurrent,
        inner: MockClient.streaming((request, body) async {
          resolvingSends++;
          if (resolvingSends == 1) throw http.ClientException('offline');
          return http.StreamedResponse(const Stream.empty(), 200);
        }),
        onConnectionFailure: (_) {
          resolving.complete();
          return endpoint.future;
        },
      );
      final resolvingPending = expectLater(
        resolvingClient.send(_graphqlRequest('{ library { id } }')),
        throwsStateError,
      );
      await resolving.future;
      resolvingCurrent = false;
      endpoint.complete(Uri.parse('http://new/api/graphql'));
      await resolvingPending;
      expect(resolvingSends, 1);

      // A switch during the retry delay prevents another send.
      fakeAsync((clock) {
        var delayCurrent = true;
        var delaySends = 0;
        Object? error;
        final delayClient = TimeoutHttpClient(
          const Duration(seconds: 5),
          retries: 1,
          retryDelay: const Duration(seconds: 1),
          isCurrentSession: () => delayCurrent,
          inner: MockClient.streaming((request, body) async {
            delaySends++;
            if (delaySends == 1) throw TimeoutException('slow');
            return http.StreamedResponse(const Stream.empty(), 200);
          }),
        );
        delayClient
            .send(_graphqlRequest('{ library { id } }'))
            .then<void>(
              (_) {},
              onError: (Object failure) {
                error = failure;
              },
            );
        clock.flushMicrotasks();
        expect(delaySends, 1);
        delayCurrent = false;
        clock.elapse(const Duration(seconds: 1));
        expect(delaySends, 1);
        expect(error, isStateError);
      });
    });

    test('a retry re-derives its headers', () async {
      // Timeout retry: the retry carries headers re-derived at retry time.
      final timeoutSent = <String?>[];
      final timeoutClient = TimeoutHttpClient(
        const Duration(seconds: 5),
        retries: 1,
        retryDelay: Duration.zero,
        inner: MockClient.streaming((request, body) async {
          timeoutSent.add(request.headers['authorization']);
          if (timeoutSent.length == 1) throw TimeoutException('app frozen');
          return http.StreamedResponse(const Stream.empty(), 200);
        }),
        retryHeaders: (headers) async => {
          ...headers..remove('Authorization'),
          'Authorization': 'Bearer refreshed',
        },
      );
      final request = _graphqlRequest('{ library { id } }')
        ..headers['Authorization'] = 'Bearer stale';
      expect((await timeoutClient.send(request)).statusCode, 200);
      expect(timeoutSent, ['Bearer stale', 'Bearer refreshed']);

      // Endpoint failover re-derives them too.
      final failoverSent = <String?>[];
      final failoverClient = TimeoutHttpClient(
        const Duration(seconds: 5),
        inner: MockClient.streaming((request, body) async {
          failoverSent.add(request.headers['authorization']);
          if (failoverSent.length == 1) throw http.ClientException('offline');
          return http.StreamedResponse(const Stream.empty(), 200);
        }),
        onConnectionFailure: (_) async => Uri.parse('http://new/api/graphql'),
        retryHeaders: (headers) async => {'Authorization': 'Bearer refreshed'},
      );
      await failoverClient.send(
        _graphqlRequest('{ library { id } }')
          ..headers['Authorization'] = 'Bearer stale',
      );
      expect(failoverSent, ['Bearer stale', 'Bearer refreshed']);

      // A throwing re-derivation abandons the retry with the original
      // failure.
      var attempts = 0;
      final throwingClient = TimeoutHttpClient(
        const Duration(seconds: 5),
        retries: 2,
        retryDelay: Duration.zero,
        inner: MockClient.streaming((request, body) async {
          attempts++;
          throw http.ClientException('offline');
        }),
        retryHeaders: (_) async => throw StateError('token unavailable'),
      );
      await expectLater(
        throwingClient.send(_graphqlRequest('{ library { id } }')),
        throwsA(isA<http.ClientException>()),
      );
      expect(attempts, 1);
    });
  });
}
