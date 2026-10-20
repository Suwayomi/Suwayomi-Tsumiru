import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;
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
  });
}
