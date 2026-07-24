// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/scanlator_dedup.dart';

import 'chapter_test_helpers.dart';

void main() {
  group('applyPreferredScanlators', () {
    test('empty preference returns list unchanged', () {
      final list = [ch(id: 1, number: 1, scanlator: 'A'),
                    ch(id: 2, number: 1, scanlator: 'B')];
      expect(applyPreferredScanlators(list, const []), same(list));
    });

    test('highest-ranked group wins its chapters', () {
      final rows = applyPreferredScanlators([
        ch(id: 1, number: 1, scanlator: 'A', sourceOrder: 0),
        ch(id: 2, number: 1, scanlator: 'B', sourceOrder: 1),
        ch(id: 3, number: 2, scanlator: 'B', sourceOrder: 2),
      ], const ['B', 'A']);
      expect(rows.map((c) => c.id), [2, 3]);
    });

    test('falls back to next rank, then source order, when unranked', () {
      final rows = applyPreferredScanlators([
        ch(id: 1, number: 1, scanlator: 'A', sourceOrder: 1),
        ch(id: 2, number: 1, scanlator: 'C', sourceOrder: 0),
      ], const ['B']); // B has nothing; C is listed first by the source
      expect(rows.single.id, 2);
    });

    test('in-progress copy beats rank; downloaded beats rank', () {
      final inProgress = applyPreferredScanlators([
        ch(id: 1, number: 1, scanlator: 'A', lastPageRead: 5),
        ch(id: 2, number: 1, scanlator: 'B'),
      ], const ['B']);
      expect(inProgress.single.id, 1);

      final downloaded = applyPreferredScanlators([
        ch(id: 1, number: 1, scanlator: 'A', isDownloaded: true),
        ch(id: 2, number: 1, scanlator: 'B'),
      ], const ['B']);
      expect(downloaded.single.id, 1);
    });

    test('a read copy does NOT beat rank (aggregate covers it)', () {
      final rows = applyPreferredScanlators([
        ch(id: 1, number: 1, scanlator: 'A', isRead: true),
        ch(id: 2, number: 1, scanlator: 'B'),
      ], const ['B']);
      expect(rows.single.id, 2);
      expect(rows.single.isRead, isTrue); // aggregate
    });

    test('aggregate state unions read/downloaded/bookmarked across copies', () {
      final row = applyPreferredScanlators([
        ch(id: 1, number: 1, scanlator: 'A',
            isRead: true, isBookmarked: true),
        ch(id: 2, number: 1, scanlator: 'B'),
      ], const ['B']).single;
      expect((row.isRead, row.isBookmarked, row.isDownloaded),
          (true, true, false));
    });

    test('same-group siblings (split chapters/v2) all survive', () {
      final rows = applyPreferredScanlators([
        ch(id: 1, number: 10, scanlator: 'A', sourceOrder: 0),
        ch(id: 2, number: 10, scanlator: 'A', sourceOrder: 1),
        ch(id: 3, number: 10, scanlator: 'B', sourceOrder: 2),
      ], const ['A']);
      expect(rows.map((c) => c.id), [1, 2]);
    });

    test('chapterNumber <= 0 passes through undeduped', () {
      final rows = applyPreferredScanlators([
        ch(id: 1, number: 0, scanlator: 'A'),
        ch(id: 2, number: 0, scanlator: 'B'),
        ch(id: 3, number: -1, scanlator: 'A'),
      ], const ['A']);
      expect(rows.length, 3);
    });

    test('blank scanlator is rankable as the Unknown group', () {
      final rows = applyPreferredScanlators([
        ch(id: 1, number: 1, scanlator: null),
        ch(id: 2, number: 1, scanlator: 'B'),
      ], const [kUnknownScanlatorGroup, 'B']);
      expect(rows.single.id, 1);
    });

    test('keepChapterId forces the in-flight copy\'s group to win', () {
      final rows = applyPreferredScanlators([
        ch(id: 1, number: 1, scanlator: 'A'),
        ch(id: 2, number: 1, scanlator: 'B'),
      ], const ['B'], keepChapterId: 1);
      expect(rows.single.id, 1);
    });

    test('preserves input order of surviving rows', () {
      final rows = applyPreferredScanlators([
        ch(id: 1, number: 2, scanlator: 'A', sourceOrder: 5),
        ch(id: 2, number: 1, scanlator: 'A', sourceOrder: 0),
      ], const ['A']);
      expect(rows.map((c) => c.id), [1, 2]);
    });

    test('tied in-progress copies resolve to the first in input order', () {
      final rows = applyPreferredScanlators([
        ch(id: 1, number: 1, scanlator: 'A', lastPageRead: 3),
        ch(id: 2, number: 1, scanlator: 'B', lastPageRead: 7),
      ], const ['B']);
      expect(rows.single.id, 1);
    });

    test('keepChapterId outranks in-progress and downloaded copies', () {
      final rows = applyPreferredScanlators([
        ch(id: 1, number: 1, scanlator: 'A', lastPageRead: 5),
        ch(id: 2, number: 1, scanlator: 'B', isDownloaded: true),
        ch(id: 3, number: 1, scanlator: 'C'),
      ], const ['A'], keepChapterId: 3);
      expect(rows.single.id, 3);
    });

    test('unknown keepChapterId falls back to normal rules', () {
      final rows = applyPreferredScanlators([
        ch(id: 1, number: 1, scanlator: 'A'),
        ch(id: 2, number: 1, scanlator: 'B'),
      ], const ['B'], keepChapterId: 99);
      expect(rows.single.id, 2);
    });

    test('keepChapterId on a passthrough (<= 0) row changes nothing', () {
      final rows = applyPreferredScanlators([
        ch(id: 1, number: 0, scanlator: 'A'),
        ch(id: 2, number: 0, scanlator: 'B'),
        ch(id: 3, number: 1, scanlator: 'B'),
      ], const ['B'], keepChapterId: 1);
      expect(rows.map((c) => c.id), [1, 2, 3]);
    });

    test('aggregation preserves the winner copy\'s other fields', () {
      final row = applyPreferredScanlators([
        ch(id: 1, number: 1, scanlator: 'A', isRead: true, sourceOrder: 4),
        ch(id: 2, number: 1, scanlator: 'B', sourceOrder: 9),
      ], const ['B']).single;
      expect((row.id, row.scanlator, row.sourceOrder, row.name),
          (2, 'B', 9, 'Chapter 1.0'));
    });

    test('NaN chapter number passes through instead of vanishing', () {
      final rows = applyPreferredScanlators([
        ch(id: 1, number: double.nan, scanlator: 'A'),
        ch(id: 2, number: 1, scanlator: 'B'),
      ], const ['B']);
      expect(rows.map((c) => c.id), [1, 2]);
    });
  });

  group('duplicateChapterIds', () {
    final list = [
      ch(id: 1, number: 1, scanlator: 'A'),
      ch(id: 2, number: 1, scanlator: 'B'),
      ch(id: 3, number: 2, scanlator: 'A'),
      ch(id: 4, number: 0, scanlator: 'A'),
      ch(id: 5, number: 0, scanlator: 'B'),
    ];
    test('returns every copy of the chapter number, self included', () {
      expect(duplicateChapterIds(list, 1), unorderedEquals([1, 2]));
    });
    test('number <= 0 returns only self', () {
      expect(duplicateChapterIds(list, 4), [4]);
    });
    test('unknown id returns only itself', () {
      expect(duplicateChapterIds(list, 99), [99]);
    });
    test('NaN number returns only self, never an empty list', () {
      final withNan = [...list, ch(id: 6, number: double.nan, scanlator: 'A')];
      expect(duplicateChapterIds(withNan, 6), [6]);
    });
  });
}
