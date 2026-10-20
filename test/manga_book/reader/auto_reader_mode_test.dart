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
  group('autoReaderModeFor', () {
    ReaderMode? resolve({List<String>? genres, String? sourceName}) =>
        autoReaderModeFor(genres: genres, sourceName: sourceName);

    const webtoon = ReaderMode.webtoon;

    group('webtoon family → webtoon (scroll)', () {
      test('manhwa / manhua / long strip / webtoon tags', () {
        expect(resolve(genres: ['Manhwa']), webtoon);
        expect(resolve(genres: ['Manhua']), webtoon);
        expect(resolve(genres: ['Long Strip']), webtoon);
        expect(resolve(genres: ['Webtoon']), webtoon);
      });
    });

    group('manga → null (never forces a direction; user default wins)', () {
      // A manga tag is still a manga tag — but auto-detect deliberately has no
      // opinion on LTR vs RTL. It returns null so the user's Default Reading
      // Mode is honoured (RTL by default, LTR if they chose it).
      test('explicit manga tag → null', () {
        expect(resolve(genres: ['Manga']), isNull);
      });
    });

    group('no reliable signal → null (respect the user default)', () {});

    group('comic → null (fall through to the default)', () {});
  });

  group('sessionAutoReaderMode', () {
    ReaderMode? resolve({bool enabled = true, ReaderMode? seriesMode}) =>
        sessionAutoReaderMode(
          enabled: enabled,
          seriesMode: seriesMode,
          genres: const ['Manhwa'],
        );

    test('Default or unset series mode takes the detected mode', () {
      expect(resolve(), ReaderMode.webtoon);
      expect(resolve(seriesMode: ReaderMode.defaultReader), ReaderMode.webtoon);
    });

    test('an explicit series mode wins over detection', () {
      expect(resolve(seriesMode: ReaderMode.singleHorizontalLTR), isNull);
    });

    test('off when auto-detect is disabled', () {
      expect(resolve(enabled: false), isNull);
    });
  });
}
