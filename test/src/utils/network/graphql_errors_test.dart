import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';
import 'package:tsumiru/src/utils/network/graphql_errors.dart';

void main() {
  test('authentication status excludes permission and server errors', () {
    for (final status in [401, 403, 500, 503]) {
      final error = OperationException(
        linkException: HttpLinkServerException(
          response: http.Response('{"errors":[]}', status),
          parsedResponse: const Response(response: {}, errors: []),
        ),
      );
      expect(isAuthenticationRequired(error), status == 401);
      final decoded = OperationException(
        linkException: HttpLinkParserException(
          originalException: ServerNotJsonException(status, '<html>'),
          originalStackTrace: StackTrace.empty,
          response: http.Response('<html>', status),
        ),
      );
      expect(isAuthenticationRequired(decoded), status == 401);
    }
    expect(
      isAuthenticationRequired(
        OperationException(
          graphqlErrors: const [GraphQLError(message: 'Forbidden')],
        ),
      ),
      isFalse,
    );
  });

  group('isConnectionError', () {
    test('classifies direct failures', () {
      expect(isConnectionError(const SocketException('x')), isTrue);
      expect(isConnectionError(TimeoutException('x')), isTrue);
      // Ambiguous failures surface rather than claiming the server is down.
      expect(isConnectionError(Exception('boom')), isFalse);
      expect(
        isConnectionError(
          OperationException(
            linkException: ServerException(
              originalException: const SocketException('down'),
              parsedResponse: null,
            ),
          ),
        ),
        isTrue,
      );
      // A GraphQL error means the server responded.
      expect(
        isConnectionError(
          OperationException(
            graphqlErrors: const [GraphQLError(message: 'Unauthorized')],
          ),
        ),
        isFalse,
      );
    });

    // A reverse proxy answering for a dead upstream is a connection loss.
    // gql_http_link wraps httpResponseDecoder throws in HttpLinkParserException
    // (a SIBLING of ServerException) — pin the real chain.
    test('gateway statuses through the real parser chain fall back', () {
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
      // A gateway status with a JSON body still counts as unreachable.
      expect(
        isConnectionError(
          OperationException(
            linkException: HttpLinkServerException(
              response: http.Response('{"errors":[]}', 502),
              parsedResponse: const Response(response: {}, errors: []),
            ),
          ),
        ),
        isTrue,
      );
    });

    test('non-gateway error pages still surface', () {
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

    // The repository throws OperationMessageException AROUND the
    // OperationException. isConnectionError does not see through it, so call
    // sites MUST unwrap first; this pins both halves of that contract.
    test(
      'the wrapper is not recognized directly, and unwrapping classifies',
      () {
        final wrapped = OperationMessageException(
          OperationException(
            linkException: ServerException(
              originalException: const SocketException('down'),
              parsedResponse: null,
            ),
          ),
        );
        expect(isConnectionError(wrapped), isFalse);
        final Object unwrapped = wrapped;
        final cause = unwrapped is OperationMessageException
            ? unwrapped.exception
            : unwrapped;
        expect(isConnectionError(cause), isTrue);
      },
    );
  });

  group('tsumiruHttpResponseDecoder', () {
    test('decodes JSON objects and rejects anything else', () {
      expect(tsumiruHttpResponseDecoder(http.Response('{"data":1}', 200)), {
        'data': 1,
      });
      expect(
        () => tsumiruHttpResponseDecoder(http.Response('', 500)),
        throwsA(isA<ServerNotJsonException>()),
      );
      expect(
        () => tsumiruHttpResponseDecoder(http.Response('[1,2]', 200)),
        throwsA(isA<ServerNotJsonException>()),
      );
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
