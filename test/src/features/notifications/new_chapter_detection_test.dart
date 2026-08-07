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
        candidates: [
          ch(1, 10, 1, 100),
          ch(2, 10, 2, 110),
          ch(3, 20, 5, 120),
        ],
        watermark: const NewChapterWatermark(fetchedAt: 0),
      );
      expect(r.groups.length, 2);
      expect(r.watermark.fetchedAt, 120);
      final manga10 = r.groups.firstWhere((g) => g.mangaId == 10);
      expect(manga10.chapters.map((c) => c.id), [1, 2]);
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

    test('recent ids outside the overlap window are pruned', () {
      final r = detectNewChapters(
        candidates: [ch(5, 10, 5, 1000000)],
        watermark: NewChapterWatermark(fetchedAt: 100, recent: {2: 100}),
        overlapMs: 1000,
      );
      // id 2 (fetchedAt 100) is far below 1000000 − 1000, so it's dropped.
      expect(r.watermark.recent.containsKey(2), isFalse);
      expect(r.watermark.recent.containsKey(5), isTrue);
    });

    test('per-series chapters are ordered by chapter number, not fetch order', () {
      final r = detectNewChapters(
        candidates: [ch(1, 10, 3, 100), ch(2, 10, 1, 130), ch(3, 10, 2, 120)],
        watermark: const NewChapterWatermark(),
      );
      expect(r.groups.single.chapters.map((c) => c.chapterNumber), [1, 2, 3]);
    });

    test('category scope filters which series notify', () {
      final r = detectNewChapters(
        candidates: [ch(1, 10, 1, 100), ch(2, 20, 1, 110)],
        watermark: const NewChapterWatermark(),
        allowedMangaIds: {10},
      );
      expect(r.groups.map((g) => g.mangaId), [10]);
      // Watermark still advances past the excluded chapter so it can't re-notify.
      expect(r.watermark.fetchedAt, 110);
    });

    test('no candidates keeps the watermark and notifies nothing', () {
      final r = detectNewChapters(
        candidates: const [],
        watermark: const NewChapterWatermark(fetchedAt: 500, recent: {9: 500}),
      );
      expect(r.groups, isEmpty);
      expect(r.watermark.fetchedAt, 500);
    });

    test('watermark round-trips through json', () {
      const wm = NewChapterWatermark(fetchedAt: 42, recent: {1: 40, 2: 41, 3: 42});
      final back = NewChapterWatermark.fromJson(wm.toJson());
      expect(back.fetchedAt, 42);
      expect(back.recent, {1: 40, 2: 41, 3: 42});
    });
  });

  group('newChaptersLabel (Komikku parity)', () {
    test('no parseable numbers -> generic count', () {
      expect(newChaptersLabel([-1, -1], 2), isA<GenericNewChapters>());
      expect((newChaptersLabel([-1, -1], 2) as GenericNewChapters).count, 2);
    });

    test('single number, no unparsed remainder -> Chapter X', () {
      final l = newChaptersLabel([12], 1) as SingleNewChapter;
      expect(l.number, '12');
      expect(l.more, 0);
    });

    test('single number with unparsed extras -> Chapter X and N more', () {
      final l = newChaptersLabel([2.5, -1, -1], 3) as SingleNewChapter;
      expect(l.number, '2.5');
      expect(l.more, 2);
    });

    test('a few numbers -> Chapters a, b, c', () {
      final l = newChaptersLabel([3, 1, 2], 3) as MultipleNewChapters;
      expect(l.numbers, ['1', '2', '3']);
      expect(l.more, 0);
    });

    test('more than the cap -> first 5 and N more', () {
      final l = newChaptersLabel([1, 2, 3, 4, 5, 6, 7], 7) as MultipleNewChapters;
      expect(l.numbers, ['1', '2', '3', '4', '5']);
      expect(l.more, 2);
    });

    test('duplicate numbers collapse', () {
      final l = newChaptersLabel([1, 1, 1], 3) as SingleNewChapter;
      expect(l.number, '1');
      expect(l.more, 2); // total 3 - 1 distinct
    });
  });
}
