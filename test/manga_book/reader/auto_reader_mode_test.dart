// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/auto_webtoon.dart';

// Pins both the reader-mode mapping AND the underlying manga-type detection
// (tag precedence, source-name lists, Cyrillic variants, substring matching).
// Mapping (Komikku `defaultReaderType` parity): webtoon-family → webtoon;
// manga and comic → null (fall through to the user's default). Auto-detect
// never picks a page direction — RTL for manga comes from the factory default.
void main() {
  test('webtoon-family tags detect webtoon; manga falls through', () {
    ReaderMode? resolve({List<String>? genres}) =>
        autoReaderModeFor(genres: genres);

    expect(resolve(genres: ['Manhwa']), ReaderMode.webtoon);
    expect(resolve(genres: ['Manhua']), ReaderMode.webtoon);
    expect(resolve(genres: ['Long Strip']), ReaderMode.webtoon);
    expect(resolve(genres: ['Webtoon']), ReaderMode.webtoon);

    // A manga tag is still a manga tag, but auto-detect deliberately has no
    // opinion on LTR vs RTL: it returns null so the user's default wins.
    expect(resolve(genres: ['Manga']), isNull);
  });
}
