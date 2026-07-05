import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:tsumiru/src/utils/network/graphql_errors.dart';

void main() {
  group('isConnectionError', () {
    test('bare SocketException is a connection error', () {
      expect(isConnectionError(const SocketException('x')), isTrue);
    });
    test('bare TimeoutException is a connection error', () {
      expect(isConnectionError(TimeoutException('x')), isTrue);
    });
    test('a plain Exception is not (ambiguous -> surface)', () {
      expect(isConnectionError(Exception('boom')), isFalse);
    });
    test('ServerException wrapping a socket error (no parsed response) is', () {
      final e = OperationException(
          linkException: ServerException(
              originalException: const SocketException('down'),
              parsedResponse: null));
      expect(isConnectionError(e), isTrue);
    });
    test('a graphql error with no link exception is not (server responded)', () {
      final e = OperationException(
          graphqlErrors: const [GraphQLError(message: 'Unauthorized')]);
      expect(isConnectionError(e), isFalse);
    });
  });

  group('tsumiruHttpResponseDecoder', () {
    test('decodes a JSON object body', () {
      expect(tsumiruHttpResponseDecoder(http.Response('{"data":1}', 200)),
          {'data': 1});
    });
    test('throws ServerNotJsonException on an empty body', () {
      expect(() => tsumiruHttpResponseDecoder(http.Response('', 500)),
          throwsA(isA<ServerNotJsonException>()));
    });
    test('throws on a JSON array (not an object)', () {
      expect(() => tsumiruHttpResponseDecoder(http.Response('[1,2]', 200)),
          throwsA(isA<ServerNotJsonException>()));
    });
    test('throws with the status code on an HTML error page', () {
      try {
        tsumiruHttpResponseDecoder(http.Response('<html>500</html>', 502));
        fail('should have thrown');
      } on ServerNotJsonException catch (e) {
        expect(e.statusCode, 502);
        expect(e.toString(), contains('502'));
      }
    });
  });
}
