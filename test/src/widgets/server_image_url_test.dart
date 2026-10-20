// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/widgets/server_image.dart';

// Representative server-emitted paths: root-relative and already carrying the
// `/api/v1` prefix.
const _icon =
    '/api/v1/extension/icon/eu.kanade.tachiyomi.extension.en.mangadex';
const _page = '/api/v1/manga/7/chapter/2/page/0';

String _build(String serverUrl, String path, {bool appendApiToUrl = false}) =>
    serverFileUrl(
      path: path,
      baseUrl: serverUrl,
      port: 4567,
      addPort: false,
      appendApiToUrl: appendApiToUrl,
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
    });

    test('appends /api/v1 only for paths the server did not prefix', () {
      // Already-prefixed paths are not doubled.
      expect(
        _build('http://127.0.0.1:4567', _page, appendApiToUrl: true),
        'http://127.0.0.1:4567$_page',
      );
      expect(
        _build('http://127.0.0.1:4567/', _icon, appendApiToUrl: true),
        'http://127.0.0.1:4567$_icon',
      );
      // An unprefixed path gets the prefix.
      expect(
        _build(
          'http://127.0.0.1:4567',
          '/manga/7/thumbnail',
          appendApiToUrl: true,
        ),
        'http://127.0.0.1:4567/api/v1/manga/7/thumbnail',
      );
      // A bare "api/" prefix counts as already prefixed.
      expect(
        _build(
          'http://127.0.0.1:4567',
          'api/v1/manga/7/thumbnail',
          appendApiToUrl: true,
        ),
        'http://127.0.0.1:4567/api/v1/manga/7/thumbnail',
      );
    });

    test('passes absolute URLs through and returns empty for a blank path', () {
      for (final url in [
        'https://cdn.tld/icon.png',
        'http://cdn.tld/icon.png',
        'file:///tmp/page.jpg',
      ]) {
        expect(_build('http://127.0.0.1:4567', url), url);
      }
      // A source restored from the offline catalog carries no iconUrl;
      // fetching the bare origin would return the WebUI's index.html.
      expect(_build('http://127.0.0.1:4567', ''), '');
    });
  });

  group('appendUiLoginToken', () {
    const url = 'http://127.0.0.1:4567$_icon';

    test('appends and encodes the token, or is a no-op', () {
      expect(appendUiLoginToken(url, 'abc.def'), '$url?token=abc.def');
      // Chapter page URLs carry server-side conversion params.
      expect(
        appendUiLoginToken('$url?format=JPEG', 'abc.def'),
        '$url?format=JPEG&token=abc.def',
      );
      expect(
        appendUiLoginToken(url, 'a+b/c=='),
        '$url?token=${Uri.encodeQueryComponent('a+b/c==')}',
      );
      expect(appendUiLoginToken(url, null), url);
      expect(appendUiLoginToken(url, ''), url);
      expect(appendUiLoginToken('', 'abc.def'), '');
    });
  });

  group('appendUiLoginTokenToWebUrl', () {
    test(
      'appends to http(s) URLs and leaves file or unparsable URLs alone',
      () {
        expect(
          appendUiLoginTokenToWebUrl('http://127.0.0.1:4567$_icon', 'abc.def'),
          'http://127.0.0.1:4567$_icon?token=abc.def',
        );
        expect(
          appendUiLoginTokenToWebUrl('https://host.tld/x.jpg', 'abc.def'),
          'https://host.tld/x.jpg?token=abc.def',
        );
        expect(
          appendUiLoginTokenToWebUrl('file:///tmp/a.jpg', 'abc.def'),
          'file:///tmp/a.jpg',
        );
        expect(
          appendUiLoginTokenToWebUrl('http://[::1', 'abc.def'),
          'http://[::1',
        );
      },
    );
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
