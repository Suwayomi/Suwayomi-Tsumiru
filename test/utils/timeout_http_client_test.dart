import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/utils/network/timeout_http_client.dart';

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
  });
}
