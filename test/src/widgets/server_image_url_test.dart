// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/web_default_server_url.dart';
import 'package:tsumiru/src/widgets/server_image.dart';

// Representative server-emitted paths: root-relative and already carrying the
// `/api/v1` prefix.
const _icon =
    '/api/v1/extension/icon/eu.kanade.tachiyomi.extension.en.mangadex';
const _page = '/api/v1/manga/7/chapter/2/page/0';

String _build(String serverUrl, String path) => serverFileUrl(
  path: path,
  baseUrl: serverUrl,
  port: 4567,
  addPort: false,
  appendApiToUrl: false,
);

void main() {
  group('serverFileUrl', () {
    test('joins a server-relative path onto the origin, keeping subpaths', () {
      expect(
        _build('http://127.0.0.1:4567', _icon),
        'http://127.0.0.1:4567$_icon',
      );
      // A trailing slash on the configured URL collapses.
      for (final url in ['http://127.0.0.1:4567/', 'http://127.0.0.1:4567//']) {
        expect(_build(url, _icon), 'http://127.0.0.1:4567$_icon', reason: url);
      }
      // A reverse-proxy subpath stays intact.
      for (final url in [
        'https://host.tld/suwayomi',
        'https://host.tld/suwayomi/',
      ]) {
        expect(
          _build(url, _icon),
          'https://host.tld/suwayomi$_icon',
          reason: url,
        );
      }
      // An existing query string and percent-encoding survive.
      expect(
        _build('http://127.0.0.1:4567/', '$_page?format=JPEG&a%20b=1'),
        'http://127.0.0.1:4567$_page?format=JPEG&a%20b=1',
      );

      // The same base-URL parsing drives the web default server URL: root,
      // sub-path, deep link and bare origins resolve to the base.
      expect(
        webDefaultServerUrl('http://127.0.0.1:4600/'),
        'http://127.0.0.1:4600',
      );
      expect(
        webDefaultServerUrl('http://127.0.0.1:4600/tsumiru/'),
        'http://127.0.0.1:4600/tsumiru',
      );
      final page = Uri.parse('http://127.0.0.1:4600/tsumiru/library');
      final base = page.resolve('/tsumiru/');
      expect(base, isNot(page));
      expect(
        webDefaultServerUrl(base.toString()),
        'http://127.0.0.1:4600/tsumiru',
      );
      expect(
        webDefaultServerUrl('http://127.0.0.1:4600/tsumiru'),
        'http://127.0.0.1:4600/tsumiru',
      );
      expect(
        webDefaultServerUrl('http://127.0.0.1:4600'),
        'http://127.0.0.1:4600',
      );
      expect(
        webDefaultServerUrl('https://example.com:8443/reader/'),
        'https://example.com:8443/reader',
      );
    });
  });

  // Off the web, a ui_login token rides an image request's header, never its
  // URL, where reverse-proxy access logs would record it.
  group('ui_login image auth (native)', () {
    const url = 'http://127.0.0.1:4567$_icon';

    test(
      'puts the token in an Authorization header and leaves the URL alone',
      () {
        expect(withUiLoginImageAuth({'X-Custom': 'kept'}, 'abc.def'), {
          'X-Custom': 'kept',
          'Authorization': 'Bearer abc.def',
        });
        expect(withUiLoginImageAuth(null, 'abc.def'), {
          'Authorization': 'Bearer abc.def',
        });
        expect(uiLoginImageUrl(url, 'abc.def'), url);
        // No token adds nothing.
        expect(withUiLoginImageAuth(null, null), isNull);
        expect(withUiLoginImageAuth({'X-Custom': 'kept'}, ''), {
          'X-Custom': 'kept',
        });
      },
    );
  });
}
