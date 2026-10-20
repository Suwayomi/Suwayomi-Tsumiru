// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/migration/domain/bulk_migration_types.dart';
import 'package:tsumiru/src/features/migration/domain/concurrency.dart';
import 'package:tsumiru/src/features/migration/domain/smart_search_engine.dart';

void main() {
  group('SmartSearchEngine.regularSearch', () {
    const engine = SmartSearchEngine();

    test('picks the highest-scoring candidate and rejects the 0.4 floor', () async {
      final r = await engine.regularSearch(
        title: 'Solo Leveling',
        search: (q) async => [
          (id: 1, title: 'Solo Max Level', thumbnailUrl: null),
          (id: 2, title: 'Solo Leveling', thumbnailUrl: null),
        ],
      );
      expect(r.mangaId, 2);
      expect(r.confidence, 1.0);

      // Komikku would shortcut a single candidate to 1.0; we compute the real
      // score and reject it below the 0.4 floor.
      final lone = await engine.regularSearch(
        title: 'Solo Leveling',
        search: (q) async => [
          (id: 9, title: 'Completely Different Manga', thumbnailUrl: null),
        ],
      );
      expect(lone.hasMatch, isFalse);
    });
  });

  group('buildSmartMatcher — first-hit-wins over priority sources', () {
    BulkMigrationEntry entry(int id, String title) =>
        BulkMigrationEntry(fromMangaId: id, fromTitle: title);

    test(
      'stops at the first source with a hit (no needless later search)',
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
      },
    );
  });
}
