// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Unit tests for the hosted web build's default server URL: page origin
// plus the app's base path (from document.baseURI, which honours the
// server-injected `<base href>`).

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/web_default_server_url.dart';

void main() {
  group('webDefaultServerUrl', () {
    test('root hosting: base "/" gives the bare origin', () {
      expect(
        webDefaultServerUrl('http://127.0.0.1:4600/'),
        'http://127.0.0.1:4600',
      );
    });

    test('sub-path hosting: base "/tsumiru/" keeps the sub-path', () {
      expect(
        webDefaultServerUrl('http://127.0.0.1:4600/tsumiru/'),
        'http://127.0.0.1:4600/tsumiru',
      );
    });

    test('deep link: the route never leaks into the URL', () {
      // On page http://127.0.0.1:4600/tsumiru/library with
      // <base href="/tsumiru/">, document.baseURI resolves to the base.
      expect(
        webDefaultServerUrl('http://127.0.0.1:4600/tsumiru/'),
        'http://127.0.0.1:4600/tsumiru',
      );
    });

    test('base without a trailing slash is kept as-is', () {
      expect(
        webDefaultServerUrl('http://127.0.0.1:4600/tsumiru'),
        'http://127.0.0.1:4600/tsumiru',
      );
    });

    test('https with a non-default port keeps scheme, host, and port', () {
      expect(
        webDefaultServerUrl('https://example.com:8443/reader/'),
        'https://example.com:8443/reader',
      );
    });

    test('bare origin without a path stays untouched', () {
      expect(
        webDefaultServerUrl('http://127.0.0.1:4600'),
        'http://127.0.0.1:4600',
      );
    });
  });
}
