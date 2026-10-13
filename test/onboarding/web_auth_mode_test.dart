// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Web gating: offered sign-in methods and the Test connection verdict.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/onboarding/data/server_resolver.dart';
import 'package:tsumiru/src/utils/network/graphql_errors.dart';
import 'package:tsumiru/src/utils/platform/web_auth_mode.dart';

// A non-JSON GraphQL answer as the app sees it: the decoder throw wrapped in
// the link parser exception, inside the operation exception.
OperationException _notJsonError(int status, String snippet) =>
    OperationException(
      linkException: HttpLinkParserException(
        originalException: ServerNotJsonException(status, snippet),
        originalStackTrace: StackTrace.empty,
        response: http.Response(snippet, status),
      ),
    );

void main() {
  group('connectionAuthChoices', () {
    test('web offers UI login and no auth only', () {
      expect(connectionAuthChoices(isWeb: true), [
        AuthType.none,
        AuthType.uiLogin,
      ]);
    });

    test('native offers every mode', () {
      expect(connectionAuthChoices(isWeb: false), AuthType.values);
    });
  });

  group('onboardingAuthChoices', () {
    test('web offers UI login only', () {
      expect(onboardingAuthChoices(isWeb: true), [AuthType.uiLogin]);
    });

    test('native offers basic, simple and UI login', () {
      expect(onboardingAuthChoices(isWeb: false), [
        AuthType.basic,
        AuthType.simpleLogin,
        AuthType.uiLogin,
      ]);
    });
  });

  group('isWebUnsupportedAuthMode', () {
    test('basic and simple login are unusable from a browser', () {
      expect(isWebUnsupportedAuthMode(AuthType.basic), isTrue);
      expect(isWebUnsupportedAuthMode(AuthType.simpleLogin), isTrue);
    });

    test('UI login, no auth and unknown stay usable', () {
      expect(isWebUnsupportedAuthMode(AuthType.uiLogin), isFalse);
      expect(isWebUnsupportedAuthMode(AuthType.none), isFalse);
      expect(isWebUnsupportedAuthMode(null), isFalse);
    });
  });

  group('webServerAuthUnsupported', () {
    test('a rejected about query reads as an unusable mode', () {
      expect(
        webServerAuthUnsupported(
          aboutError: OperationException(
            graphqlErrors: [GraphQLError(message: 'Unauthorized')],
          ),
          detectedAuthType: null,
        ),
        isTrue,
      );
    });

    test('a transport failure still reads as unreachable', () {
      expect(
        webServerAuthUnsupported(
          aboutError: OperationException(
            linkException: NetworkException(
              uri: Uri.parse('http://server:4567/api/graphql'),
              originalException: http.ClientException('Failed to fetch'),
            ),
          ),
          detectedAuthType: null,
        ),
        isFalse,
      );
    });

    test('detected basic login reads as an unusable mode', () {
      // Simple login stays out: the browser probe cannot tell it apart, so it
      // reads as UI login and is caught after sign-in instead.
      expect(
        webServerAuthUnsupported(
          aboutError: null,
          detectedAuthType: AuthType.basic,
        ),
        isTrue,
      );
    });

    test('detected UI login, no auth or unknown stays usable', () {
      for (final detected in [AuthType.uiLogin, AuthType.none, null]) {
        expect(
          webServerAuthUnsupported(
            aboutError: null,
            detectedAuthType: detected,
          ),
          isFalse,
          reason: '$detected',
        );
      }
    });

    test('a readable 404 "Not Found" reads as Basic-gated', () {
      expect(
        webServerAuthUnsupported(
          aboutError: _notJsonError(404, 'Not Found'),
          detectedAuthType: null,
        ),
        isTrue,
      );
    });

    test('a 404 with another body stays unreachable', () {
      expect(
        webServerAuthUnsupported(
          aboutError: _notJsonError(404, '<html>proxy 404</html>'),
          detectedAuthType: null,
        ),
        isFalse,
      );
    });

    test('a non-404 non-JSON error stays unreachable', () {
      expect(
        webServerAuthUnsupported(
          aboutError: _notJsonError(500, '<html>error</html>'),
          detectedAuthType: null,
        ),
        isFalse,
      );
    });
  });
}
