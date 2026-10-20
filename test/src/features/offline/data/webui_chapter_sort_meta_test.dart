// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_types.dart';
import 'package:tsumiru/src/features/offline/data/webui_chapter_sort_meta.dart';

void main() {
  test('WebUI wire keys, axis parsing and the alphabetical flag', () {
    // Match WebUI's own wire keys exactly (no device/app prefix, since both
    // are listed as GLOBAL_METADATA_KEYS on the WebUI side).
    expect(kWebUiSortByMetaKey, 'webUI_sortBy');
    expect(kWebUiReverseMetaKey, 'webUI_reverse');

    for (final axis in ChapterSortAxis.values) {
      if (axis == ChapterSortAxis.alphabetical) continue;
      expect(chapterSortAxisFromMetaValue(axis.name), axis);
    }

    for (final value in [true, false]) {
      expect(
        chapterSortAscendingFromMetaValue(chapterSortAscendingToMetaValue(value)),
        value,
      );
    }

    final alphabeticalKey = MangaMetaKeys.chapterSortAlphabetical.key;
    expect(
      chapterSortAxisFromMeta(
        (key) => {
          alphabeticalKey: 'true',
          kWebUiSortByMetaKey: 'chapterNumber',
        }[key],
      ),
      ChapterSortAxis.alphabetical,
      reason: 'the alphabetical flag wins over a webUI_sortBy left in place',
    );
  });
}
