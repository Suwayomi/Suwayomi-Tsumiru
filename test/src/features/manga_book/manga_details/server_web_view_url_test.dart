// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/server_web_url.dart';

void main() {
  test('webview url builds with or without a base trailing slash', () {
    const url = 'https://example.com/series/a?b=c#d';
    expect(
      serverWebViewUrl('http://host:4567/api/v1', url),
      'http://host:4567/api/v1/webview#$url',
    );
    expect(
      serverWebViewUrl('http://host:4567/api/v1/', url),
      'http://host:4567/api/v1/webview#$url',
    );
  });
}
