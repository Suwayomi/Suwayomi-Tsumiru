// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/missing_chapters.dart';

void main() {
  test('reader gap counts skipped chapters in the direction of travel', () {
    expect(chapterGap(higher: 13, lower: 10), 2);
    expect(chapterGap(higher: 1, lower: 50), 0);
    expect(chapterGap(higher: 18, lower: 16.5), 1);
    expect(chapterGap(higher: 10, lower: 8.5), 1);
    expect(chapterGap(higher: 8.5, lower: 10), 0);
    expect(chapterGap(higher: 10, lower: 1.1), 8);
    expect(chapterGap(higher: 1.9, lower: 1), 0);
    expect(chapterGap(higher: 2, lower: 1), 0);
    expect(chapterGap(higher: -1, lower: 10), 0);
    expect(chapterGap(higher: 10, lower: -1), 0);
    expect(chapterGap(higher: null, lower: 10), 0);
    expect(chapterGap(higher: 10, lower: double.nan), 0);
    expect(chapterGap(higher: double.infinity, lower: 10), 0);
  });
  test('empty and unknown chapter lists have no gaps', () {
    expect(findMissingChapterRanges(const []), isEmpty);
    expect(findMissingChapterRanges(const [-1, -1]), isEmpty);
  });

  test('finds gaps before and between available chapters', () {
    final ranges = findMissingChapterRanges(const [4, 6, 10]);

    expect(ranges.map((range) => (range.lowerChapter, range.higherChapter)), [
      (0, 4),
      (4, 6),
      (6, 10),
    ]);
    expect(ranges.map((range) => range.count), [3, 1, 3]);
  });

  test('floors decimals and ignores repeated scanlator versions', () {
    final ranges = findMissingChapterRanges(const [1, 1, 1.1, 1.99, 2, 4, 4.5]);

    expect(ranges, hasLength(1));
    expect(ranges.single.lowerChapter, 2);
    expect(ranges.single.higherChapter, 4);
    expect(ranges.single.count, 1);
  });

  test('ignores non-finite chapter numbers', () {
    expect(
      findMissingChapterRanges(const [double.nan, double.infinity, 1, 2]),
      isEmpty,
    );
  });
}
