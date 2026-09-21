// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
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
    test('parses every ChapterSortAxis value by exact wire string', () {
      for (final axis in ChapterSortAxis.values) {
        expect(chapterSortAxisFromMetaValue(axis.name), axis);
      }
    });

    test('null (no meta key at all) -> null', () {
      expect(chapterSortAxisFromMetaValue(null), isNull);
    });

    test('unknown/legacy value -> null, never throws', () {
      expect(chapterSortAxisFromMetaValue('not-a-real-axis'), isNull);
      expect(chapterSortAxisFromMetaValue(''), isNull);
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
    test('every ChapterSortAxis maps to a ChapterSort and back to itself', () {
      for (final axis in ChapterSortAxis.values) {
        final sort = chapterSortFromWebUiAxis(axis);
        expect(
          webUiAxisFromChapterSort(sort),
          axis,
          reason: '$axis -> $sort must map back to $axis',
        );
      }
    });

    test('the two name-mismatched pairs map correctly in both directions', () {
      expect(
        webUiAxisFromChapterSort(ChapterSort.uploadDate),
        ChapterSortAxis.uploadedAt,
      );
      expect(
        chapterSortFromWebUiAxis(ChapterSortAxis.uploadedAt),
        ChapterSort.uploadDate,
      );
      expect(
        webUiAxisFromChapterSort(ChapterSort.fetchedDate),
        ChapterSortAxis.fetchedAt,
      );
      expect(
        chapterSortFromWebUiAxis(ChapterSortAxis.fetchedAt),
        ChapterSort.fetchedDate,
      );
    });

    test('the two name-matched pairs map straightforwardly', () {
      expect(
        webUiAxisFromChapterSort(ChapterSort.source),
        ChapterSortAxis.source,
      );
      expect(
        webUiAxisFromChapterSort(ChapterSort.chapterNumber),
        ChapterSortAxis.chapterNumber,
      );
    });

    test('alphabetical has no WebUI equivalent', () {
      expect(webUiAxisFromChapterSort(ChapterSort.alphabetical), isNull);
    });

    test('every ChapterSort value is handled (compile-time exhaustiveness '
        'guard: this test itself would fail to compile if a new value were '
        'added to ChapterSort without updating webUiAxisFromChapterSort)',
        () {
      for (final sort in ChapterSort.values) {
        // Must not throw for any sort value.
        webUiAxisFromChapterSort(sort);
      }
      expect(ChapterSort.values.length, 5);
    });
  });
}
