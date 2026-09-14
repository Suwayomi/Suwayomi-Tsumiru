// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/scanlator_dedup.dart';

import 'chapter_test_helpers.dart';

void main() {
  group('read/delete mutation matching', () {
    test('propagates across confident alternate releases', () {
      final chapters = [
        ch(id: 1, number: 1, scanlator: 'A'),
        ch(id: 2, number: 1, scanlator: 'B'),
      ];
      expect(expandIdsForDuplicates(chapters, [1]), [1, 2]);
      expect(expandIdsForDuplicates(chapters, [2]), [1, 2]);
    });

    test('does not propagate between a regular and special chapter', () {
      final chapters = [
        ch(id: 1, number: 6, name: 'Chapter 6', scanlator: 'A'),
        ch(id: 2, number: 6, name: 'Special 6', scanlator: 'A'),
      ];
      expect(expandIdsForDuplicates(chapters, [1]), [1]);
    });

    test('does not propagate across restarted season numbering', () {
      final chapters = [
        ch(id: 1, number: 1, name: 'Season 1 Chapter 1', scanlator: 'A'),
        ch(id: 2, number: 1, name: 'Season 2 Chapter 1', scanlator: 'B'),
      ];
      expect(expandIdsForDuplicates(chapters, [1]), [1]);
    });

    test('propagates a confidently matched Chapter 0', () {
      final chapters = [
        ch(id: 1, number: 0, scanlator: 'A'),
        ch(id: 2, number: 0, scanlator: 'B'),
      ];
      expect(expandIdsForDuplicates(chapters, [1]), [1, 2]);
    });

    test('does not propagate same-scanlator rows', () {
      final chapters = [
        ch(id: 1, number: 1, scanlator: 'A'),
        ch(id: 2, number: 1, scanlator: 'A'),
      ];
      expect(expandIdsForDuplicates(chapters, [1]), [1]);
    });

    test('does not propagate otherwise-identical non-adjacent rows', () {
      final chapters = [
        ch(id: 1, number: 1, scanlator: 'A', sourceOrder: 0),
        ch(id: 2, number: 2, scanlator: 'C', sourceOrder: 1),
        ch(id: 3, number: 1, scanlator: 'B', sourceOrder: 2),
      ];
      expect(expandIdsForDuplicates(chapters, [1]), [1]);
      expect(expandIdsForDuplicates(chapters, [3]), [3]);
    });

    test('unions matches for bulk read/delete actions', () {
      final chapters = [
        ch(id: 1, number: 1, scanlator: 'A', sourceOrder: 0),
        ch(id: 2, number: 1, scanlator: 'B', sourceOrder: 1),
        ch(id: 3, number: 2, scanlator: 'A', sourceOrder: 2),
        ch(id: 4, number: 2, scanlator: 'B', sourceOrder: 3),
      ];
      expect(expandIdsForDuplicates(chapters, [1, 3]), [1, 2, 3, 4]);
    });

    test('identity when the raw chapter list is unavailable', () {
      expect(expandIdsForDuplicates(null, [1, 3]), [1, 3]);
    });
  });

  group('read-state reconciliation', () {
    test('marks only unread releases in confident groups', () {
      final chapters = [
        ch(id: 1, number: 1, scanlator: 'A', isRead: true),
        ch(id: 2, number: 1, scanlator: 'B'),
        ch(id: 3, number: 2, scanlator: 'A'),
        ch(id: 4, number: 2, scanlator: 'B'),
      ];
      expect(reconcileIdsForReadNumbers(chapters), [2]);
    });

    test('does not reconcile uncertain same-number rows', () {
      final chapters = [
        ch(id: 1, number: 6, name: 'Chapter 6', scanlator: 'A',
            isRead: true),
        ch(id: 2, number: 6, name: 'Special 6', scanlator: 'B'),
        ch(id: 3, number: 1, name: 'Season 1 Chapter 1', scanlator: 'A',
            isRead: true),
        ch(id: 4, number: 1, name: 'Season 2 Chapter 1', scanlator: 'B'),
      ];
      expect(reconcileIdsForReadNumbers(chapters), isEmpty);
    });
  });
}
