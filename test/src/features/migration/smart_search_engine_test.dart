// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/migration/domain/bulk_migration_types.dart';
import 'package:tsumiru/src/features/migration/domain/concurrency.dart';
import 'package:tsumiru/src/features/migration/domain/smart_search_engine.dart';
import 'package:tsumiru/src/features/migration/domain/string_similarity.dart';

void main() {
  group('normalizedLevenshteinSimilarity', () {
    test('identical strings score 1.0', () {
      expect(normalizedLevenshteinSimilarity('Solo Leveling', 'Solo Leveling'),
          1.0);
    });
    test('two empty strings score 1.0', () {
      expect(normalizedLevenshteinSimilarity('', ''), 1.0);
    });
    test('one empty string scores 0.0', () {
      expect(normalizedLevenshteinSimilarity('abc', ''), 0.0);
    });
    test('a near match scores high, an unrelated one scores low', () {
      expect(normalizedLevenshteinSimilarity('Solo Leveling', 'Solo Levelling'),
          greaterThan(0.9));
      expect(
          normalizedLevenshteinSimilarity('Solo Leveling', 'Berserk'), lessThan(0.4));
    });
  });

  group('sanitizeQuery', () {
    test('trims separator chars from the ends', () {
      expect(sanitizeQuery('  - Naruto : '), 'Naruto');
    });
    test('normalizes fancy quotes and dashes', () {
      expect(sanitizeQuery('‘Hero’ — tale'), "'Hero' - tale");
    });
    test('drops a removePrefix', () {
      expect(sanitizeQuery('re:Zero', removePrefix: 're:'), 'Zero');
    });
  });

  group('SmartSearchEngine.regularSearch', () {
    const engine = SmartSearchEngine();

    test('picks the highest-scoring eligible candidate', () async {
      final r = await engine.regularSearch(
        title: 'Solo Leveling',
        search: (q) async => [
          (id: 1, title: 'Solo Max Level', thumbnailUrl: null),
          (id: 2, title: 'Solo Leveling', thumbnailUrl: null),
        ],
      );
      expect(r.mangaId, 2);
      expect(r.confidence, 1.0);
    });

    test('a lone unrelated candidate is NOT auto-accepted as 1.0', () async {
      // Komikku would shortcut a single candidate to 1.0; we compute the real
      // score and reject it below the 0.4 floor.
      final r = await engine.regularSearch(
        title: 'Solo Leveling',
        search: (q) async => [(id: 9, title: 'Completely Different Manga', thumbnailUrl: null)],
      );
      expect(r.hasMatch, isFalse);
    });

    test('sets singleCandidate as provenance when one result comes back',
        () async {
      final r = await engine.regularSearch(
        title: 'Berserk',
        search: (q) async => [(id: 5, title: 'Berserk', thumbnailUrl: null)],
      );
      expect(r.hasMatch, isTrue);
      expect(r.singleCandidate, isTrue);
      expect(r.confidence, 1.0);
    });

    test('excludes the source manga id from candidates', () async {
      final r = await engine.regularSearch(
        title: 'Berserk',
        excludeId: 5,
        search: (q) async => [(id: 5, title: 'Berserk', thumbnailUrl: null)],
      );
      expect(r.hasMatch, isFalse);
    });

    test('empty candidate list is a no-match', () async {
      final r = await engine.regularSearch(
        title: 'Anything',
        search: (q) async => [],
      );
      expect(r.hasMatch, isFalse);
    });
  });

  group('buildSmartMatcher — first-hit-wins over priority sources', () {
    BulkMigrationEntry entry(int id, String title) =>
        BulkMigrationEntry(fromMangaId: id, fromTitle: title);

    test('returns the match from the first source that has one', () async {
      final searched = <String>[];
      final matcher = buildSmartMatcher(
        targetSourceIds: ['srcA', 'srcB'],
        rateLimiter: RateLimiter(minInterval: Duration.zero),
        search: (sourceId, query) async {
          searched.add(sourceId);
          if (sourceId == 'srcA') return []; // no hit on the first source
          return [(id: 42, title: 'Solo Leveling', thumbnailUrl: null)];
        },
      );
      final outcome = await matcher(entry(1, 'Solo Leveling'), CancelToken());
      expect(outcome.toMangaId, 42);
      expect(searched, ['srcA', 'srcB']);
    });

    test('stops at the first source with a hit (no needless later search)',
        () async {
      final searched = <String>[];
      final matcher = buildSmartMatcher(
        targetSourceIds: ['srcA', 'srcB'],
        rateLimiter: RateLimiter(minInterval: Duration.zero),
        search: (sourceId, query) async {
          searched.add(sourceId);
          return [(id: 7, title: 'Berserk', thumbnailUrl: null)];
        },
      );
      final outcome = await matcher(entry(1, 'Berserk'), CancelToken());
      expect(outcome.toMangaId, 7);
      expect(searched, ['srcA'], reason: 'first hit wins — srcB not queried');
    });

    test('no match on any source yields an empty outcome', () async {
      final matcher = buildSmartMatcher(
        targetSourceIds: ['srcA'],
        rateLimiter: RateLimiter(minInterval: Duration.zero),
        search: (sourceId, query) async => [(id: 1, title: 'Unrelated Thing', thumbnailUrl: null)],
      );
      final outcome = await matcher(entry(1, 'Solo Leveling'), CancelToken());
      expect(outcome.hasMatch, isFalse);
    });
  });
}
