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
  group('kWebUiSortByMetaKey / kWebUiReverseMetaKey', () {
    test('match WebUI\'s own wire keys exactly (no device/app prefix, since '
        'both are listed as GLOBAL_METADATA_KEYS on the WebUI side)', () {
      expect(kWebUiSortByMetaKey, 'webUI_sortBy');
      expect(kWebUiReverseMetaKey, 'webUI_reverse');
    });
  });

  group('chapterSortAxisFromMetaValue', () {
    test('parses every WebUI axis value by exact wire string', () {
      for (final axis in ChapterSortAxis.values) {
        if (axis == ChapterSortAxis.alphabetical) continue;
        expect(chapterSortAxisFromMetaValue(axis.name), axis);
      }
    });
  });

  group('chapterSortAxisFromMeta', () {
    String? Function(String) metaOf(Map<String, String> meta) =>
        (key) => meta[key];
    final alphabeticalKey = MangaMetaKeys.chapterSortAlphabetical.key;

    test('the alphabetical flag wins over a webUI_sortBy left in place', () {
      expect(
        chapterSortAxisFromMeta(
          metaOf({
            alphabeticalKey: 'true',
            kWebUiSortByMetaKey: 'chapterNumber',
          }),
        ),
        ChapterSortAxis.alphabetical,
      );
    });
  });

  group('chapterSortAscendingFromMetaValue', () {});

  group('chapterSortAscendingToMetaValue', () {
    test('round-trips through chapterSortAscendingFromMetaValue', () {
      for (final value in [true, false]) {
        expect(
          chapterSortAscendingFromMetaValue(
            chapterSortAscendingToMetaValue(value),
          ),
          value,
        );
      }
    });
  });

  group('ChapterSort <-> ChapterSortAxis mapping', () {});
}
