// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/missing_chapters.dart';

void main() {
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
