// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

/// A contiguous run of whole chapter numbers absent from a chapter catalogue.
///
/// [lowerChapter] and [higherChapter] are the present chapter numbers on either
/// side. The lower bound is zero when chapters before the first available one
/// are missing.
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

/// Finds missing whole-numbered chapters using the same decimal semantics as
/// Mihon: chapter 8.5 counts as chapter 8 when checking the gap to chapter 10.
/// Unknown chapter numbers (negative values) are ignored, and repeated numbers
/// from multiple scanlators count only once.
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
