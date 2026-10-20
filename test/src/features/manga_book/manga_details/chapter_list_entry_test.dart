// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/chapter_list_entry.dart';

import 'chapter_test_helpers.dart';

void main() {
  for (final ascending in [false, true]) {
    for (final numbers in [
      [10, 1],
      [1, 10],
      [10, 1, 20],
      [20, 10, 1],
      [10, 20, 1],
      [1, 20, 10],
      [20, 1, 10],
      [1, 10, 20],
    ]) {
      test(
        'retains all catalogue gaps in order $numbers ascending=$ascending',
        () {
          final chapters = [
            for (final number in numbers)
              ch(id: number, number: number.toDouble()),
          ];
          final entries = buildMangaChapterListEntries(
            sortedChapters: chapters,
            visibleChapterIds: numbers.toSet(),
            ascending: ascending,
          );
          expect(
            entries.whereType<MangaChapterEntry>().map((e) => e.chapter.id),
            numbers,
          );
          expect(
            entries
                .whereType<MissingChaptersEntry>()
                .map((e) => e.count)
                .toList()
              ..sort(),
            numbers.length == 2 ? [8] : [8, 9],
          );
        },
      );
    }
  }
}
