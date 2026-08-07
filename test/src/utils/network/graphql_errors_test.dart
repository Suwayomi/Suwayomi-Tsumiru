import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';
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
    // A reverse proxy answering for a dead upstream is a connection loss:
    // the user's server never spoke, only the middleman did. The decoder's
    // throw arrives wrapped in the PARSER exception (gql_http_link wraps
    // httpResponseDecoder throws in HttpLinkParserException, a SIBLING of
    // ServerException) — pin the real chain: a fabricated ServerException
    // wrapper made an earlier version of this pass while production failed.
    test(
      'gateway statuses through the real parser-exception chain fall back',
      () {
        for (final status in [502, 503, 504, 521, 524]) {
          final e = OperationException(
            linkException: HttpLinkParserException(
              originalException: ServerNotJsonException(status, "<html>"),
              originalStackTrace: StackTrace.empty,
              response: http.Response('<html>', status),
            ),
          );
          expect(isConnectionError(e), isTrue, reason: 'HTTP $status');
        }
      },
    );
    test('non-gateway error pages still surface (500, captive-portal 200)', () {
      for (final status in [500, 200, 520, 525]) {
        final e = OperationException(
          linkException: HttpLinkParserException(
            originalException: ServerNotJsonException(status, "<html>"),
            originalStackTrace: StackTrace.empty,
            response: http.Response('<html>', status),
          ),
        );
        expect(isConnectionError(e), isFalse, reason: 'HTTP $status');
      }
    });
    test('a gateway status with a JSON body still counts as unreachable', () {
      final e = OperationException(
        linkException: HttpLinkServerException(
          response: http.Response('{"errors":[]}', 502),
          parsedResponse: const Response(response: {}, errors: []),
        ),
      );
      expect(isConnectionError(e), isTrue);
    });
    test('ServerException wrapping a socket error (no parsed response) is', () {
      final e = OperationException(
        linkException: ServerException(
          originalException: const SocketException('down'),
          parsedResponse: null,
        ),
      );
      expect(isConnectionError(e), isTrue);
    });
    test(
      'a graphql error with no link exception is not (server responded)',
      () {
        final e = OperationException(
          graphqlErrors: const [GraphQLError(message: 'Unauthorized')],
        );
        expect(isConnectionError(e), isFalse);
      },
    );

    // The repository layer throws OperationMessageException AROUND the
    // OperationException — the shape every UI mutation actually sees.
    // isConnectionError does not see through it (importing the wrapper here
    // would cycle), so call sites MUST unwrap first; this pair pins both
    // halves of that contract.
    test('wrapped OperationMessageException is NOT recognized directly', () {
      final wrapped = OperationMessageException(
        OperationException(
          linkException: ServerException(
            originalException: const SocketException('down'),
            parsedResponse: null,
          ),
        ),
      );
      expect(isConnectionError(wrapped), isFalse);
    });
    test('call-site unwrap of OperationMessageException classifies right', () {
      final Object wrapped = OperationMessageException(
        OperationException(
          linkException: ServerException(
            originalException: const SocketException('down'),
            parsedResponse: null,
          ),
        ),
      );
      final cause = wrapped is OperationMessageException
          ? wrapped.exception
          : wrapped;
      expect(isConnectionError(cause), isTrue);
    });
  });

  group('tsumiruHttpResponseDecoder', () {
    test('decodes a JSON object body', () {
      expect(tsumiruHttpResponseDecoder(http.Response('{"data":1}', 200)), {
        'data': 1,
      });
    });
    test('throws ServerNotJsonException on an empty body', () {
      expect(
        () => tsumiruHttpResponseDecoder(http.Response('', 500)),
        throwsA(isA<ServerNotJsonException>()),
      );
    });
    test('throws on a JSON array (not an object)', () {
      expect(
        () => tsumiruHttpResponseDecoder(http.Response('[1,2]', 200)),
        throwsA(isA<ServerNotJsonException>()),
      );
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
