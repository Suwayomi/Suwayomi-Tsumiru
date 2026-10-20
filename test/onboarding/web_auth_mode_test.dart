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
  test('web capabilities and unsupported auth modes', () {
    expect(connectionAuthChoices(isWeb: true), [
      AuthType.none,
      AuthType.uiLogin,
    ]);

    // Basic and simple login are unusable from a browser.
    expect(isWebUnsupportedAuthMode(AuthType.basic), isTrue);
    expect(isWebUnsupportedAuthMode(AuthType.simpleLogin), isTrue);

    // A rejected about query reads as an unusable mode.
    expect(
      webServerAuthUnsupported(
        aboutError: OperationException(
          graphqlErrors: [GraphQLError(message: 'Unauthorized')],
        ),
        detectedAuthType: null,
      ),
      isTrue,
    );

    // Simple login stays out: the browser probe cannot tell it apart, so it
    // reads as UI login and is caught after sign-in instead.
    expect(
      webServerAuthUnsupported(
        aboutError: null,
        detectedAuthType: AuthType.basic,
      ),
      isTrue,
    );

    // A readable 404 "Not Found" reads as Basic-gated.
    expect(
      webServerAuthUnsupported(
        aboutError: _notJsonError(404, 'Not Found'),
        detectedAuthType: null,
      ),
      isTrue,
    );
  });
}
