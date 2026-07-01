// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/auto_webtoon.dart';

// Pins the Komikku MangaType.kt port: tag precedence, source-name lists,
// Cyrillic variants, and the WEBTOON/MANHWA/MANHUA → webtoon mapping.
void main() {
  group('detectsWebtoon', () {
    test('manhwa tag → true', () {
      expect(detectsWebtoon(genres: ['Manhwa']), isTrue);
    });

    test('manhua tag → true', () {
      expect(detectsWebtoon(genres: ['Manhua']), isTrue);
    });

    test('long strip tag → true', () {
      expect(detectsWebtoon(genres: ['Long Strip']), isTrue);
    });

    test('webtoon tag → true', () {
      expect(detectsWebtoon(genres: ['Webtoon']), isTrue);
    });

    test('manga tag beats manhwa tag (precedence) → false', () {
      expect(detectsWebtoon(genres: ['Manhwa', 'Manga']), isFalse);
    });

    test('manga tag beats webtoon source (precedence) → false', () {
      expect(
        detectsWebtoon(genres: ['Manga'], sourceName: 'Toonily'),
        isFalse,
      );
    });

    test('comic tag → false', () {
      expect(detectsWebtoon(genres: ['Comic']), isFalse);
    });

    test('comic tag beats manhua tag (precedence) → false', () {
      expect(detectsWebtoon(genres: ['Manhua', 'Comic']), isFalse);
    });

    test('no tags, no source → false', () {
      expect(detectsWebtoon(genres: null), isFalse);
      expect(detectsWebtoon(genres: [], sourceName: null), isFalse);
    });

    test('unrelated tags → false', () {
      expect(detectsWebtoon(genres: ['Action', 'Romance']), isFalse);
    });

    test('manhwa source name (manhwa18) → true', () {
      expect(detectsWebtoon(genres: [], sourceName: 'Manhwa18'), isTrue);
    });

    test('webtoon source name (toonily → manhwa list) → true', () {
      expect(detectsWebtoon(genres: null, sourceName: 'Toonily'), isTrue);
    });

    test('webtoon source name (webtoons) → true', () {
      expect(detectsWebtoon(genres: [], sourceName: 'Webtoons.com'), isTrue);
    });

    test('comic source name (readcomiconline) → false', () {
      expect(
        detectsWebtoon(genres: [], sourceName: 'ReadComicOnline'),
        isFalse,
      );
    });

    test('manhua source name (manhuaus) → true', () {
      expect(detectsWebtoon(genres: [], sourceName: 'ManhuaUS'), isTrue);
    });

    test('Cyrillic манхва tag → true', () {
      expect(detectsWebtoon(genres: ['Манхва']), isTrue);
    });

    test('Cyrillic маньхуа tag → true', () {
      expect(detectsWebtoon(genres: ['Маньхуа']), isTrue);
    });

    test('Cyrillic манга tag wins precedence → false', () {
      expect(detectsWebtoon(genres: ['Манга', 'Манхва']), isFalse);
    });

    test('tag match is substring, case-insensitive (Komikku contains)', () {
      expect(detectsWebtoon(genres: ['Korean Manhwa (Color)']), isTrue);
      expect(detectsWebtoon(genres: ['WEBTOON']), isTrue);
    });

    test('random source name → false', () {
      expect(detectsWebtoon(genres: [], sourceName: 'MangaDex'), isFalse);
    });
  });
}
