// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/widgets/server_image.dart';

// Representative server-emitted paths: root-relative and already carrying the
// `/api/v1` prefix.
const _icon = '/api/v1/extension/icon/eu.kanade.tachiyomi.extension.en.mangadex';
const _page = '/api/v1/manga/7/chapter/2/page/0';

String _build(
  String serverUrl,
  String path, {
  bool appendApiToUrl = false,
}) =>
    serverFileUrl(
      path: path,
      baseUrl: serverUrl,
      port: 4567,
      addPort: false,
      appendApiToUrl: appendApiToUrl,
    );

void main() {
  group('serverFileUrl', () {
    test('joins a server-relative icon path onto a clean origin', () {
      expect(
        _build('http://127.0.0.1:4567', _icon),
        'http://127.0.0.1:4567$_icon',
      );
    });

    test('collapses a trailing slash on the configured server URL', () {
      for (final url in ['http://127.0.0.1:4567/', 'http://127.0.0.1:4567//']) {
        expect(_build(url, _icon), 'http://127.0.0.1:4567$_icon', reason: url);
      }
    });

    test('does not duplicate /api/v1 when appendApiToUrl is on', () {
      // The reader prefetcher goes through getServerFile, whose
      // appendApiToUrl defaults to true, with an already-prefixed page URL.
      expect(
        _build('http://127.0.0.1:4567', _page, appendApiToUrl: true),
        'http://127.0.0.1:4567$_page',
      );
      expect(
        _build('http://127.0.0.1:4567/', _icon, appendApiToUrl: true),
        'http://127.0.0.1:4567$_icon',
      );
    });

    test('still appends /api/v1 for a path the server did not prefix', () {
      expect(
        _build('http://127.0.0.1:4567', '/manga/7/thumbnail',
            appendApiToUrl: true),
        'http://127.0.0.1:4567/api/v1/manga/7/thumbnail',
      );
    });

    test('treats a bare "api/" prefix as already prefixed', () {
      expect(
        _build('http://127.0.0.1:4567', 'api/v1/manga/7/thumbnail',
            appendApiToUrl: true),
        'http://127.0.0.1:4567/api/v1/manga/7/thumbnail',
      );
    });

    test('keeps a reverse-proxy subpath intact', () {
      for (final url in ['https://host.tld/suwayomi', 'https://host.tld/suwayomi/']) {
        expect(_build(url, _icon), 'https://host.tld/suwayomi$_icon',
            reason: url);
      }
    });

    test('passes absolute URLs through untouched', () {
      for (final url in [
        'https://cdn.tld/icon.png',
        'http://cdn.tld/icon.png',
        'file:///tmp/page.jpg',
      ]) {
        expect(_build('http://127.0.0.1:4567', url), url);
      }
    });

    test('returns empty for a blank path so callers skip the request', () {
      // A source restored from the offline catalog carries no iconUrl;
      // fetching the bare origin would return the WebUI's index.html.
      expect(_build('http://127.0.0.1:4567', ''), '');
    });

    test('preserves an existing query string and percent-encoding', () {
      expect(
        _build('http://127.0.0.1:4567/', '$_page?format=JPEG&a%20b=1'),
        'http://127.0.0.1:4567$_page?format=JPEG&a%20b=1',
      );
    });
  });

  group('appendUiLoginToken', () {
    const url = 'http://127.0.0.1:4567$_icon';

    test('uses ? when the URL has no query', () {
      expect(appendUiLoginToken(url, 'abc.def'), '$url?token=abc.def');
    });

    test('uses & when the URL already has a query', () {
      // Chapter page URLs carry server-side conversion params.
      expect(
        appendUiLoginToken('$url?format=JPEG', 'abc.def'),
        '$url?format=JPEG&token=abc.def',
      );
    });

    test('percent-encodes the token', () {
      expect(
        appendUiLoginToken(url, 'a+b/c=='),
        '$url?token=${Uri.encodeQueryComponent('a+b/c==')}',
      );
    });

    test('is a no-op without a token, and on an empty URL', () {
      expect(appendUiLoginToken(url, null), url);
      expect(appendUiLoginToken(url, ''), url);
      expect(appendUiLoginToken('', 'abc.def'), '');
    });
  });
}
