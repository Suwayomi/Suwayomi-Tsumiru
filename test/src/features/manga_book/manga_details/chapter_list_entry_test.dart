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
  test('inserts initial and internal gaps in ascending order', () {
    final chapters = [
      ch(id: 1, number: 4),
      ch(id: 2, number: 6),
      ch(id: 3, number: 10),
    ];

    expect(
      _labels(
        buildMangaChapterListEntries(
          sortedChapters: chapters,
          visibleChapterIds: {1, 2, 3},
          ascending: true,
        ),
      ),
      ['missing:3', 4, 'missing:1', 6, 'missing:3', 10],
    );
  });

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

  test('filters chapter rows without turning present chapters into gaps', () {
    final chapters = [
      ch(id: 1, number: 1),
      ch(id: 2, number: 2),
      ch(id: 4, number: 4),
    ];

    expect(
      _labels(
        buildMangaChapterListEntries(
          sortedChapters: chapters,
          visibleChapterIds: {1, 4},
          ascending: true,
        ),
      ),
      [1, 'missing:1', 4],
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

  test('keeps each real gap to one entry in a non-numeric sort', () {
    final chapters = [
      ch(id: 1, number: 1),
      ch(id: 10, number: 10),
      ch(id: 2, number: 2),
      ch(id: 11, number: 10, scanlator: 'other'),
    ];

    expect(
      _labels(
        buildMangaChapterListEntries(
          sortedChapters: chapters,
          visibleChapterIds: {1, 2, 10, 11},
          ascending: true,
        ),
      ).where((label) => label == 'missing:7'),
      hasLength(1),
    );
  });

  test('returns no warning-only list when all chapters are filtered out', () {
    expect(
      buildMangaChapterListEntries(
        sortedChapters: [ch(id: 10, number: 10)],
        visibleChapterIds: const {},
        ascending: true,
      ),
      isEmpty,
    );
  });
}
