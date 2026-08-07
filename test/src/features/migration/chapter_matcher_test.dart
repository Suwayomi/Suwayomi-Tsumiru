// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/migration/domain/chapter_matcher.dart';

ChapterState ch({
  required int id,
  required double number,
  String name = '',
  bool read = false,
  bool bookmark = false,
  int lastPage = 0,
}) =>
    ChapterState(
      id: id,
      chapterNumber: number,
      name: name,
      isRead: read,
      isBookmarked: bookmark,
      lastPageRead: lastPage,
    );

void main() {
  group('matchChapterState — number matching', () {
    test('exact number carries read state to the matching target', () {
      final r = matchChapterState(
        source: [ch(id: 1, number: 5, read: true)],
        target: [ch(id: 11, number: 5), ch(id: 12, number: 6)],
      );
      expect(r.unmatchedState, 0);
      expect(r.patches, hasLength(1));
      expect(r.patches.single.id, 11);
      expect(r.patches.single.isRead, true);
    });

    test('float-noise within tolerance still matches (5.0 vs 5.001)', () {
      final r = matchChapterState(
        source: [ch(id: 1, number: 5.001, read: true)],
        target: [ch(id: 11, number: 5.0)],
      );
      expect(r.patches.single.id, 11);
    });

    test('"Chapter 1" must NOT match "Chapter 10" (no substring collision)', () {
      final r = matchChapterState(
        source: [ch(id: 1, number: 1, name: 'Chapter 1', read: true)],
        target: [ch(id: 110, number: 10, name: 'Chapter 10')],
      );
      // 1 != 10 by number, and name fallback is disabled for recognized
      // numbers, so this is unmatched — never a false read.
      expect(r.patches, isEmpty);
      expect(r.unmatchedState, 1);
    });

    test('distinct numbers do not collide even with similar names', () {
      final r = matchChapterState(
        source: [
          ch(id: 1, number: 1, name: 'Vol 1', read: true),
          ch(id: 2, number: 10, name: 'Vol 10', read: true),
        ],
        target: [
          ch(id: 101, number: 1, name: 'Vol 1'),
          ch(id: 110, number: 10, name: 'Vol 10'),
        ],
      );
      expect(r.unmatchedState, 0);
      expect({for (final p in r.patches) p.id}, {101, 110});
    });
  });

  group('matchChapterState — negative-number name fallback (oneshots)', () {
    test('unrecognized number matches target by exact lowercased name', () {
      final r = matchChapterState(
        source: [ch(id: 1, number: -1, name: 'Oneshot', read: true)],
        target: [ch(id: 11, number: -1, name: 'oneshot')],
      );
      expect(r.patches.single.id, 11);
      expect(r.unmatchedState, 0);
    });

    test('negative name fallback is exact, not substring', () {
      final r = matchChapterState(
        source: [ch(id: 1, number: -1, name: 'Extra', read: true)],
        target: [ch(id: 11, number: -1, name: 'Extra Chapter')],
      );
      expect(r.patches, isEmpty);
      expect(r.unmatchedState, 1);
    });

    test('all-negative series with no name overlap carries nothing', () {
      final r = matchChapterState(
        source: [ch(id: 1, number: -1, name: 'A', read: true)],
        target: [ch(id: 11, number: -1, name: 'B')],
      );
      expect(r.patches, isEmpty);
      expect(r.unmatchedState, 1);
    });
  });

  group('matchChapterState — monotonicity (never rewind/un-read)', () {
    test('does not emit when target already read', () {
      final r = matchChapterState(
        source: [ch(id: 1, number: 5, read: true)],
        target: [ch(id: 11, number: 5, read: true)],
      );
      expect(r.patches, isEmpty);
    });

    test('several source chapters on one target take the max position', () {
      final r = matchChapterState(
        source: [
          ch(id: 1, number: 5, lastPage: 3),
          ch(id: 2, number: 5.0001, lastPage: 9),
        ],
        target: [ch(id: 11, number: 5, lastPage: 1)],
      );
      expect(r.patches.single.id, 11);
      expect(r.patches.single.lastPageRead, 9);
    });

    test('carries position even when the source chapter is read', () {
      final r = matchChapterState(
        source: [ch(id: 1, number: 5, read: true, lastPage: 7)],
        target: [ch(id: 11, number: 5, lastPage: 2)],
      );
      final p = r.patches.single;
      expect(p.isRead, true);
      expect(p.lastPageRead, 7);
    });

    test('chapters with no state are ignored', () {
      final r = matchChapterState(
        source: [ch(id: 1, number: 5)],
        target: [ch(id: 11, number: 5)],
      );
      expect(r.patches, isEmpty);
      expect(r.unmatchedState, 0);
    });
  });
}
