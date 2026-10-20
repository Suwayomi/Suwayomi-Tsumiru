// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/chapter_list_entry.dart';

import 'chapter_test_helpers.dart';

List<Object> _labels(List<MangaChapterListEntry> entries) => [
  for (final entry in entries)
    switch (entry) {
      MangaChapterEntry() => entry.chapter.chapterNumber,
      MissingChaptersEntry() => 'missing:${entry.count}',
    },
];

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

  test('puts the initial gap at the end in descending order', () {
    final chapters = [
      ch(id: 3, number: 10),
      ch(id: 2, number: 6),
      ch(id: 1, number: 4),
    ];

    expect(
      _labels(
        buildMangaChapterListEntries(
          sortedChapters: chapters,
          visibleChapterIds: {1, 2, 3},
          ascending: false,
        ),
      ),
      [10, 'missing:3', 6, 'missing:1', 4, 'missing:3'],
    );
  });

  test('places a gap after a real chapter zero instead of before it', () {
    final chapters = [ch(id: 0, number: 0), ch(id: 10, number: 10)];

    expect(
      _labels(
        buildMangaChapterListEntries(
          sortedChapters: chapters,
          visibleChapterIds: {0, 10},
          ascending: true,
        ),
      ),
      [0, 'missing:9', 10],
    );
  });

  test('merges notices made adjacent by a display filter', () {
    final chapters = [
      ch(id: 1, number: 1),
      ch(id: 3, number: 3),
      ch(id: 5, number: 5),
    ];

    expect(
      _labels(
        buildMangaChapterListEntries(
          sortedChapters: chapters,
          visibleChapterIds: {1, 5},
          ascending: true,
        ),
      ),
      [1, 'missing:2', 5],
    );
  });
}
