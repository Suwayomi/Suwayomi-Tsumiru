// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/scanlator_dedup.dart';

import 'chapter_test_helpers.dart';

void main() {
  final chapters = [
    ch(id: 1, number: 1, scanlator: 'A', isRead: true),
    ch(id: 2, number: 1, scanlator: 'B'),
    ch(id: 3, number: 2, scanlator: 'A'),
    ch(id: 4, number: 2, scanlator: 'B'),
  ];

  group('expandIdsForDuplicates', () {
    test('unions sibling ids per chapter number', () {
      expect(expandIdsForDuplicates(chapters, [1]), unorderedEquals([1, 2]));
      expect(expandIdsForDuplicates(chapters, [1, 3]),
          unorderedEquals([1, 2, 3, 4]));
    });
    test('identity when the raw list is unavailable', () {
      expect(expandIdsForDuplicates(null, [1, 3]), [1, 3]);
    });
  });

  group('reconcileIdsForReadNumbers', () {
    test('returns unread copies of read numbers only', () {
      // number 1 has a read copy (id 1) → its unread sibling id 2 qualifies;
      // number 2 has no read copy → ids 3,4 untouched.
      expect(reconcileIdsForReadNumbers(chapters), [2]);
    });
    test('empty when nothing to mark', () {
      expect(
        reconcileIdsForReadNumbers(
            [ch(id: 1, number: 1, scanlator: 'A')]),
        isEmpty,
      );
    });
  });

  group('expandIdsForDuplicates (delete propagation)', () {
    test('covers a hidden downloaded copy', () {
      final downloaded = [
        ch(id: 1, number: 1, scanlator: 'A', isDownloaded: true),
        ch(id: 2, number: 1, scanlator: 'B', isDownloaded: true),
      ];
      expect(
          expandIdsForDuplicates(downloaded, [1]), unorderedEquals([1, 2]));
    });
  });
}
