// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/notifications/domain/new_chapter_detection.dart';

NotifiableChapter ch(int id, int mangaId, double number, int fetchedAt) =>
    (id: id, mangaId: mangaId, chapterNumber: number, fetchedAt: fetchedAt);

void main() {
  group('detectNewChapters', () {
    test('groups fresh chapters by manga and advances the watermark', () {
      final r = detectNewChapters(
        candidates: [ch(1, 10, 1, 100), ch(2, 10, 2, 110), ch(3, 20, 5, 120)],
        watermark: const NewChapterWatermark(fetchedAt: 0),
      );
      expect(r.groups.length, 2);
      expect(r.watermark.fetchedAt, 120);
      final manga10 = r.groups.firstWhere((g) => g.mangaId == 10);
      expect(manga10.chapters.map((c) => c.id), [1, 2]);

      // Per-series chapters are ordered by chapter number, not fetch order.
      final ordered = detectNewChapters(
        candidates: [ch(1, 10, 3, 100), ch(2, 10, 1, 130), ch(3, 10, 2, 120)],
        watermark: const NewChapterWatermark(),
      );
      expect(ordered.groups.single.chapters.map((c) => c.chapterNumber), [
        1,
        2,
        3,
      ]);

      // The default overlap is 5 minutes in seconds, the unit of fetchedAt.
      expect(kDefaultOverlapSeconds, 300);

      // The watermark round-trips through json.
      const wm = NewChapterWatermark(
        fetchedAt: 42,
        recent: {1: 40, 2: 41, 3: 42},
      );
      final back = NewChapterWatermark.fromJson(wm.toJson());
      expect(back.fetchedAt, 42);
      expect(back.recent, {1: 40, 2: 41, 3: 42});
    });

    test('an already-notified chapter in the overlap window is not re-sent', () {
      // Prior run notified id 2 (fetchedAt 110). Re-query returns it again plus
      // a late-committed id 3 below the mark — 3 fires, 2 is deduped.
      final r = detectNewChapters(
        candidates: [ch(2, 10, 2, 110), ch(3, 10, 3, 105)],
        watermark: const NewChapterWatermark(fetchedAt: 110, recent: {2: 110}),
      );
      final ids = r.groups.expand((g) => g.chapters).map((c) => c.id).toList();
      expect(ids, [3]); // 2 deduped, 3 (late, below the mark) caught
      expect(r.watermark.recent.keys.toSet(), {2, 3});
    });
  });
}
