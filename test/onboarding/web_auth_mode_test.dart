// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Unit tests for the web UI-login-only gating: which sign-in methods the
// browser build offers, and when its Test connection reports an unusable
// server mode instead of an unreachable server.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/onboarding/data/server_resolver.dart';
import 'package:tsumiru/src/utils/platform/web_auth_mode.dart';

void main() {
  group('connectionAuthChoices', () {
    test('web offers UI login and no auth only', () {
      expect(
        connectionAuthChoices(isWeb: true),
        [AuthType.none, AuthType.uiLogin],
      );
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
      expect(
        onboardingAuthChoices(isWeb: false),
        [AuthType.basic, AuthType.simpleLogin, AuthType.uiLogin],
      );
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

    test('detected basic or simple login reads as an unusable mode', () {
      for (final detected in [AuthType.basic, AuthType.simpleLogin]) {
        expect(
          webServerAuthUnsupported(
            aboutError: null,
            detectedAuthType: detected,
          ),
          isTrue,
          reason: '$detected',
        );
      }
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
  });
}
