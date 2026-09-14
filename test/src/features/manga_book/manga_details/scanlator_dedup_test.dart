// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/scanlator_dedup.dart';

import 'chapter_test_helpers.dart';

void main() {
  group('filterPreferredScanlators', () {
    test('empty preference returns list unchanged', () {
      final list = [
        ch(id: 1, number: 1, scanlator: 'A'),
        ch(id: 2, number: 1, scanlator: 'B'),
      ];
      expect(filterPreferredScanlators(list, const []), same(list));
    });

    test('keeps every row from every selected group without folding', () {
      final rows = filterPreferredScanlators([
        ch(id: 1, number: 1, scanlator: 'A'),
        ch(id: 2, number: 1, scanlator: 'B'),
        ch(id: 3, number: 1, scanlator: 'A'),
        ch(id: 4, number: 2, scanlator: 'C'),
      ], const ['A', 'B']);
      expect(rows.map((c) => c.id), [1, 2, 3]);
    });

    test('preserves regular and special chapters with the same number', () {
      final rows = filterPreferredScanlators([
        ch(id: 1, number: 6, name: 'Chapter 6', scanlator: 'A'),
        ch(id: 2, number: 6, name: 'Special 6', scanlator: 'A'),
        ch(id: 3, number: 6, name: 'Chapter 6', scanlator: 'B'),
      ], const ['A']);
      expect(rows.map((c) => c.id), [1, 2]);
    });

    test('preserves every season when chapter numbering restarts', () {
      final rows = filterPreferredScanlators([
        ch(id: 1, number: 0, name: 'Season 1 Chapter 0', scanlator: 'A'),
        ch(id: 2, number: 1, name: 'Season 1 Chapter 1', scanlator: 'A'),
        ch(id: 3, number: 0, name: 'Season 2 Chapter 0', scanlator: 'A'),
        ch(id: 4, number: 1, name: 'Season 2 Chapter 1', scanlator: 'A'),
      ], const ['A']);
      expect(rows.map((c) => c.id), [1, 2, 3, 4]);
    });

    test('preserves all 536 rows in a large restarted-numbering series', () {
      final chapters = [
        for (var id = 0; id < 536; id++)
          ch(
            id: id,
            number: (id % 183).toDouble(),
            name: 'Season ${id ~/ 183 + 1} Chapter ${id % 183}',
            scanlator: 'A',
            sourceOrder: id,
          ),
      ];
      expect(filterPreferredScanlators(chapters, const ['A']), hasLength(536));
    });

    test('keeps an open row from an unselected group', () {
      final rows = filterPreferredScanlators([
        ch(id: 1, number: 1, scanlator: 'A'),
        ch(id: 2, number: 1, scanlator: 'B'),
        ch(id: 3, number: 2, scanlator: 'B'),
      ], const ['B'], keepChapterId: 1);
      expect(rows.map((c) => c.id), [1, 2, 3]);
    });

    test('blank scanlator is selectable as Unknown', () {
      final rows = filterPreferredScanlators([
        ch(id: 1, number: 1),
        ch(id: 2, number: 2, scanlator: 'A'),
      ], const [kUnknownScanlatorGroup]);
      expect(rows.map((c) => c.id), [1]);
    });

    test('does not aggregate state between same-number rows', () {
      final rows = filterPreferredScanlators([
        ch(id: 1, number: 1, scanlator: 'A', isRead: true),
        ch(id: 2, number: 1, scanlator: 'B'),
      ], const ['B']);
      expect(rows.single.id, 2);
      expect(rows.single.isRead, isFalse);
    });
  });

  group('applyReaderSessionScanlator', () {
    test('follows the opening scanlator for confident alternate releases', () {
      final rows = applyReaderSessionScanlator([
        ch(id: 1, number: 1, name: 'Chapter 1', scanlator: 'A', sourceOrder: 0),
        ch(id: 2, number: 1, name: 'Chapter 1', scanlator: 'B', sourceOrder: 1),
        ch(id: 3, number: 2, name: 'Chapter 2', scanlator: 'B', sourceOrder: 2),
        ch(id: 4, number: 2, name: 'Chapter 2', scanlator: 'A', sourceOrder: 3),
      ], scanlatorGroup: 'A', keepChapterId: 1);
      expect(rows.map((c) => c.id), [1, 4]);
    });

    test('uses saved preferences before source order when session group is missing', () {
      final rows = applyReaderSessionScanlator([
        ch(id: 1, number: 1, name: 'Chapter 1', scanlator: 'A', sourceOrder: 0),
        ch(id: 2, number: 1, name: 'Chapter 1', scanlator: 'B', sourceOrder: 1),
      ], scanlatorGroup: 'C', preferred: const ['B', 'A']);
      expect(rows.single.id, 2);
    });

    test('offline selects the actually downloaded release without copying flags', () {
      final rows = applyReaderSessionScanlator([
        ch(id: 1, number: 1, name: 'Chapter 1', scanlator: 'A', sourceOrder: 0),
        ch(id: 2, number: 1, name: 'Chapter 1', scanlator: 'B', sourceOrder: 1,
            isDownloaded: true),
      ], scanlatorGroup: 'A', offline: true);
      expect(rows.single.id, 2);
      expect(rows.single.isDownloaded, isTrue);
    });

    test('keeps regular and special same-number chapters independent', () {
      final rows = applyReaderSessionScanlator([
        ch(id: 1, number: 6, name: 'Chapter 6', scanlator: 'A', sourceOrder: 0),
        ch(id: 2, number: 6, name: 'Special 6', scanlator: 'A', sourceOrder: 1),
      ], scanlatorGroup: 'A');
      expect(rows.map((c) => c.id), [1, 2]);
    });

    test('different names across scanlators are not assumed duplicates', () {
      final rows = applyReaderSessionScanlator([
        ch(id: 1, number: 1, name: 'Season 1 Chapter 1', scanlator: 'A', sourceOrder: 0),
        ch(id: 2, number: 1, name: 'Season 2 Chapter 1', scanlator: 'B', sourceOrder: 1),
      ], scanlatorGroup: 'A');
      expect(rows.map((c) => c.id), [1, 2]);
    });

    test('same-scanlator equal-name rows are kept independent', () {
      final rows = applyReaderSessionScanlator([
        ch(id: 1, number: 1, name: 'Chapter 1', scanlator: 'A', sourceOrder: 0),
        ch(id: 2, number: 1, name: 'Chapter 1', scanlator: 'A', sourceOrder: 1),
      ], scanlatorGroup: 'A');
      expect(rows.map((c) => c.id), [1, 2]);
    });

    test('preserves repeated chapter numbers from separate seasons', () {
      final rows = applyReaderSessionScanlator([
        ch(id: 1, number: 1, name: 'Chapter 1', scanlator: 'A', sourceOrder: 0),
        ch(id: 2, number: 1, name: 'Chapter 1', scanlator: 'B', sourceOrder: 1),
        ch(id: 3, number: 2, name: 'Chapter 2', scanlator: 'A', sourceOrder: 2),
        ch(id: 4, number: 1, name: 'Chapter 1', scanlator: 'A', sourceOrder: 3),
        ch(id: 5, number: 1, name: 'Chapter 1', scanlator: 'B', sourceOrder: 4),
      ], scanlatorGroup: 'A');
      expect(rows.map((c) => c.id), [1, 3, 4]);
    });

    test('keeps the exact open release', () {
      final rows = applyReaderSessionScanlator([
        ch(id: 1, number: 1, name: 'Chapter 1', scanlator: 'A', sourceOrder: 0),
        ch(id: 2, number: 1, name: 'Chapter 1', scanlator: 'B', sourceOrder: 1),
      ], scanlatorGroup: 'A', keepChapterId: 2);
      expect(rows.single.id, 2);
    });
  });

  group('mutation release matching', () {
    test('uses the reader match for read/delete and reconciliation', () {
      final rows = [
        ch(id: 1, number: 1, scanlator: 'A', isRead: true),
        ch(id: 2, number: 1, scanlator: 'B'),
      ];
      expect(duplicateChapterIds(rows, 1), [1, 2]);
      expect(expandIdsForDuplicates(rows, [1]), [1, 2]);
      expect(reconcileIdsForReadNumbers(rows), [2]);
    });
  });
}
