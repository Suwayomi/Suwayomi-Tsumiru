// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
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

    test('never yields alphabetical: WebUI has no such webUI_sortBy value', () {
      expect(chapterSortAxisFromMetaValue('alphabetical'), isNull);
    });

    test('null (no meta key at all) -> null', () {
      expect(chapterSortAxisFromMetaValue(null), isNull);
    });

    test('unknown/legacy value -> null, never throws', () {
      expect(chapterSortAxisFromMetaValue('not-a-real-axis'), isNull);
      expect(chapterSortAxisFromMetaValue(''), isNull);
    });
  });

  group('chapterSortAxisFromMeta', () {
    String? Function(String) metaOf(Map<String, String> meta) =>
        (key) => meta[key];
    final alphabeticalKey = MangaMetaKeys.chapterSortAlphabetical.key;

    test('no sort meta at all -> null (app-wide default applies)', () {
      expect(chapterSortAxisFromMeta(metaOf({})), isNull);
    });

    test('webUI_sortBy alone resolves to its axis', () {
      expect(
        chapterSortAxisFromMeta(metaOf({kWebUiSortByMetaKey: 'uploadedAt'})),
        ChapterSortAxis.uploadedAt,
      );
    });

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

    test('a legacy "false" flag falls through to webUI_sortBy', () {
      expect(
        chapterSortAxisFromMeta(
          metaOf({alphabeticalKey: 'false', kWebUiSortByMetaKey: 'source'}),
        ),
        ChapterSortAxis.source,
      );
    });
  });

  group('chapterSortReverseFromMetaValue', () {
    test('exact WebUI wire format: literally "true"/"false", not a general '
        'boolean parse', () {
      expect(chapterSortReverseFromMetaValue('true'), isTrue);
      expect(chapterSortReverseFromMetaValue('false'), isFalse);
    });

    test('anything other than the literal string "true" is false, mirroring '
        "WebUI's own `value === 'true'` comparison", () {
      expect(chapterSortReverseFromMetaValue('True'), isFalse);
      expect(chapterSortReverseFromMetaValue('1'), isFalse);
      expect(chapterSortReverseFromMetaValue('yes'), isFalse);
    });

    test('null (no meta key at all) -> null, distinct from false', () {
      expect(chapterSortReverseFromMetaValue(null), isNull);
    });
  });

  group('chapterSortReverseToMetaValue', () {
    test('produces exactly "true"/"false", case-sensitive', () {
      expect(chapterSortReverseToMetaValue(true), 'true');
      expect(chapterSortReverseToMetaValue(false), 'false');
    });

    test('round-trips through chapterSortReverseFromMetaValue', () {
      for (final value in [true, false]) {
        expect(
          chapterSortReverseFromMetaValue(chapterSortReverseToMetaValue(value)),
          value,
        );
      }
    });
  });

  group('ChapterSort <-> ChapterSortAxis mapping', () {
    test('every ChapterSort maps to an axis and back to itself', () {
      for (final sort in ChapterSort.values) {
        final axis = chapterSortAxisFromChapterSort(sort);
        expect(
          chapterSortFromAxis(axis),
          sort,
          reason: '$sort -> $axis must map back to $sort',
        );
      }
      expect(ChapterSort.values.length, ChapterSortAxis.values.length);
    });

    test('the two name-mismatched pairs map correctly in both directions', () {
      expect(
        chapterSortAxisFromChapterSort(ChapterSort.uploadDate),
        ChapterSortAxis.uploadedAt,
      );
      expect(
        chapterSortFromAxis(ChapterSortAxis.uploadedAt),
        ChapterSort.uploadDate,
      );
      expect(
        chapterSortAxisFromChapterSort(ChapterSort.fetchedDate),
        ChapterSortAxis.fetchedAt,
      );
      expect(
        chapterSortFromAxis(ChapterSortAxis.fetchedAt),
        ChapterSort.fetchedDate,
      );
    });

    test('alphabetical maps to its own Tsumiru-only axis', () {
      expect(
        chapterSortAxisFromChapterSort(ChapterSort.alphabetical),
        ChapterSortAxis.alphabetical,
      );
    });
  });
}
