// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

/// Counts skipped whole chapters, including filtered chapters; backwards numbering is not a gap.
int chapterGap({required double? higher, required double? lower}) {
  if (higher == null ||
      lower == null ||
      !higher.isFinite ||
      !lower.isFinite ||
      higher < 0 ||
      lower < 0) {
    return 0;
  }
  return max(0, higher.floor() - lower.floor() - 1);
}

/// Bounds are present chapters; [lowerChapter] is zero for a gap before the first chapter.
class MissingChapterRange {
  const MissingChapterRange({
    required this.lowerChapter,
    required this.higherChapter,
  });

  final int lowerChapter;
  final int higherChapter;

  int get count => higherChapter - lowerChapter - 1;

  String get id => '$lowerChapter-$higherChapter';
}

/// Floors decimals (8.5 counts as 8), ignores negative numbers, and counts duplicates once.
List<MissingChapterRange> findMissingChapterRanges(
  Iterable<double> chapterNumbers,
) {
  final chapters =
      chapterNumbers
          .where((number) => number >= 0 && number.isFinite)
          .map((number) => number.floor())
          .toSet()
          .toList()
        ..sort();

  if (chapters.isEmpty) return const [];

  final ranges = <MissingChapterRange>[];
  var lower = 0;
  for (final higher in chapters) {
    if (higher > lower + 1) {
      ranges.add(
        MissingChapterRange(lowerChapter: lower, higherChapter: higher),
      );
    }
    lower = max(lower, higher);
  }
  return ranges;
}
