// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/downloads/data/delete_chapters_settings_repository.dart';

ChapterDto _ch(int id) => Fragment$ChapterDto(
  id: id,
  mangaId: 1,
  name: 'c$id',
  chapterNumber: id.toDouble(),
  sourceOrder: id,
  isRead: false,
  isBookmarked: false,
  isDownloaded: true,
  lastPageRead: 0,
  pageCount: 10,
  fetchedAt: '0',
  uploadDate: '0',
  lastReadAt: '0',
  url: '',
  meta: const <Fragment$ChapterDto$meta>[],
);

void main() {
  group('DeleteChaptersSettings.fromMeta', () {
    test('defaults to all-off when the keys are absent', () {
      final s = DeleteChaptersSettings.fromMeta(const {});
      expect(s.deleteManuallyMarkedRead, isFalse);
      expect(s.deleteWhileReading, 0);
      expect(s.deleteWithBookmark, isFalse);
    });

    test('parses the webUI_ global-meta keys and rejects bad values', () {
      final parsed = DeleteChaptersSettings.fromMeta(const {
        kDeleteChaptersManuallyMarkedReadKey: 'true',
        kDeleteChaptersWhileReadingKey: '2',
        kDeleteChaptersWithBookmarkKey: 'true',
      });
      expect(parsed.deleteManuallyMarkedRead, isTrue);
      expect(parsed.deleteWhileReading, 2);
      expect(parsed.deleteWithBookmark, isTrue);

      final bad = DeleteChaptersSettings.fromMeta(const {
        kDeleteChaptersManuallyMarkedReadKey: 'false',
        kDeleteChaptersWhileReadingKey: 'nonsense',
        kDeleteChaptersWithBookmarkKey: '1',
      });
      expect(bad.deleteManuallyMarkedRead, isFalse);
      expect(bad.deleteWhileReading, 0);
      expect(bad.deleteWithBookmark, isFalse, reason: '"1" is not "true"');

      // The exact key names the WebUI reads and writes.
      expect(
        kDeleteChaptersManuallyMarkedReadKey,
        'webUI_deleteChaptersManuallyMarkedRead',
      );
      expect(
        kDeleteChaptersWhileReadingKey,
        'webUI_deleteChaptersWhileReading',
      );
      expect(
        kDeleteChaptersWithBookmarkKey,
        'webUI_deleteChaptersWithBookmark',
      );
    });
  });

  group('chapterIdToDeleteWhileReading (N-behind target)', () {
    // Ascending display order: reading forward = increasing index.
    final asc = [_ch(1), _ch(2), _ch(3), _ch(4), _ch(5)];
    // Descending display order (newest first): reading forward = decreasing idx.
    final desc = [_ch(5), _ch(4), _ch(3), _ch(2), _ch(1)];

    test('both reading orders target N-1 behind, or nothing at slot 0', () {
      expect(chapterIdToDeleteWhileReading(asc, true, 3, 0), isNull);
      expect(chapterIdToDeleteWhileReading(desc, false, 3, 0), isNull);

      // Ascending: slot 1 = the just-read chapter, N = N-1 behind it.
      expect(chapterIdToDeleteWhileReading(asc, true, 3, 1), 3); // just read
      expect(chapterIdToDeleteWhileReading(asc, true, 3, 2), 2); // one behind
      expect(chapterIdToDeleteWhileReading(asc, true, 3, 3), 1); // two behind

      // Descending walks the other way so it still targets behind.
      expect(chapterIdToDeleteWhileReading(desc, false, 3, 1), 3);
      expect(chapterIdToDeleteWhileReading(desc, false, 3, 2), 2);
      expect(chapterIdToDeleteWhileReading(desc, false, 3, 3), 1);
    });

    test('never targets a chapter ahead, out of range, or an unknown id', () {
      expect(chapterIdToDeleteWhileReading(asc, true, 1, 2), isNull);
      expect(chapterIdToDeleteWhileReading(desc, false, 1, 2), isNull);
      expect(chapterIdToDeleteWhileReading(asc, true, 999, 1), isNull);
    });
  });
}
