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

      test('substring, case-insensitive (Komikku contains semantics)', () {
        expect(resolve(genres: ['Korean Manhwa (Color)']), webtoon);
        expect(resolve(genres: ['WEBTOON']), webtoon);
      });

      test('Cyrillic манхва / маньхуа tags', () {
        expect(resolve(genres: ['Манхва']), webtoon);
        expect(resolve(genres: ['Маньхуа']), webtoon);
      });

      test('source-name lists (manhwa / manhua / webtoon)', () {
        expect(resolve(genres: const [], sourceName: 'Manhwa18'), webtoon);
        expect(resolve(genres: null, sourceName: 'Toonily'), webtoon);
        expect(resolve(genres: const [], sourceName: 'Webtoons.com'), webtoon);
        expect(resolve(genres: const [], sourceName: 'ManhuaUS'), webtoon);
      });

      test('Asura Scans (always long-strip, only content genres) → webtoon', () {
        // Real-world: Asura entries carry no type tag and its source name isn't
        // in Komikku's list; detecting it by source name (our addition) keeps
        // these on scroll instead of the fallback.
        expect(
          resolve(
            genres: ['Action', 'Adventure', 'Fantasy'],
            sourceName: 'Asura Scans (EN)',
          ),
          webtoon,
        );
      });
    });

    group('manga → null (never forces a direction; user default wins)', () {
      // A manga tag is still a manga tag — but auto-detect deliberately has no
      // opinion on LTR vs RTL. It returns null so the user's Default Reading
      // Mode is honoured (RTL by default, LTR if they chose it).
      test('explicit manga tag → null', () {
        expect(resolve(genres: ['Manga']), isNull);
      });

      test('manga tag beats a manhwa tag / webtoon source, still → null', () {
        // Precedence still lands on the manga bucket (not webtoon), so no
        // webtoon override — it just falls through to the default.
        expect(resolve(genres: ['Manhwa', 'Manga']), isNull);
        expect(resolve(genres: ['Manga'], sourceName: 'Toonily'), isNull);
      });

      test('Cyrillic манга tag → null', () {
        expect(resolve(genres: ['Манга', 'Манхва']), isNull);
      });
    });

    group('no reliable signal → null (respect the user default)', () {
      test('untagged / null genres', () {
        expect(resolve(genres: null), isNull);
        expect(resolve(genres: const [], sourceName: null), isNull);
      });

      test('content genres only, genuinely unknown source → null', () {
        // A source we don't recognise, with no type tag, has no reliable
        // signal — it must fall to the user's default.
        expect(
          resolve(
            genres: ['Action', 'Adventure', 'Fantasy'],
            sourceName: 'MangaDex',
          ),
          isNull,
        );
        expect(
          resolve(genres: ['Action', 'Romance'], sourceName: 'SomeUnknownSite'),
          isNull,
        );
      });
    });

    group('comic → null (fall through to the default)', () {
      test('comic tag', () {
        expect(resolve(genres: ['Comic']), isNull);
      });

      test('comic tag beats a manhua tag (precedence)', () {
        expect(resolve(genres: ['Manhua', 'Comic']), isNull);
      });

      test('comic source name', () {
        expect(resolve(genres: const [], sourceName: 'ReadComicOnline'), isNull);
      });
    });
  });
}
