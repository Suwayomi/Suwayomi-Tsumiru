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

    test('parses the server values from the webUI_ global-meta keys', () {
      final s = DeleteChaptersSettings.fromMeta(const {
        kDeleteChaptersManuallyMarkedReadKey: 'true',
        kDeleteChaptersWhileReadingKey: '2',
        kDeleteChaptersWithBookmarkKey: 'true',
      });
      expect(s.deleteManuallyMarkedRead, isTrue);
      expect(s.deleteWhileReading, 2);
      expect(s.deleteWithBookmark, isTrue);
    });

    test('treats anything but "true" as false, and bad numbers as 0', () {
      final s = DeleteChaptersSettings.fromMeta(const {
        kDeleteChaptersManuallyMarkedReadKey: 'false',
        kDeleteChaptersWhileReadingKey: 'nonsense',
        kDeleteChaptersWithBookmarkKey: '1',
      });
      expect(s.deleteManuallyMarkedRead, isFalse);
      expect(s.deleteWhileReading, 0);
      expect(s.deleteWithBookmark, isFalse, reason: '"1" is not "true"');
    });

    test('uses the exact key names the WebUI reads/writes', () {
      expect(kDeleteChaptersManuallyMarkedReadKey,
          'webUI_deleteChaptersManuallyMarkedRead');
      expect(kDeleteChaptersWhileReadingKey, 'webUI_deleteChaptersWhileReading');
      expect(
          kDeleteChaptersWithBookmarkKey, 'webUI_deleteChaptersWithBookmark');
    });
  });

  group('chapterIdToDeleteWhileReading (N-behind target)', () {
    // Ascending display order: reading forward = increasing index.
    final asc = [_ch(1), _ch(2), _ch(3), _ch(4), _ch(5)];
    // Descending display order (newest first): reading forward = decreasing idx.
    final desc = [_ch(5), _ch(4), _ch(3), _ch(2), _ch(1)];

    test('slots <= 0 deletes nothing', () {
      expect(chapterIdToDeleteWhileReading(asc, true, 3, 0), isNull);
    });

    test('ascending: slot 1 = the just-read chapter, N = N-1 behind it', () {
      expect(chapterIdToDeleteWhileReading(asc, true, 3, 1), 3); // just read
      expect(chapterIdToDeleteWhileReading(asc, true, 3, 2), 2); // one behind
      expect(chapterIdToDeleteWhileReading(asc, true, 3, 3), 1); // two behind
    });

    test('descending: walks the other way so it still targets behind', () {
      expect(chapterIdToDeleteWhileReading(desc, false, 3, 1), 3);
      expect(chapterIdToDeleteWhileReading(desc, false, 3, 2), 2);
      expect(chapterIdToDeleteWhileReading(desc, false, 3, 3), 1);
    });

    test('never targets a chapter ahead / out of range', () {
      expect(chapterIdToDeleteWhileReading(asc, true, 1, 2), isNull);
      expect(chapterIdToDeleteWhileReading(desc, false, 1, 2), isNull);
    });

    test('unknown read chapter id deletes nothing', () {
      expect(chapterIdToDeleteWhileReading(asc, true, 999, 1), isNull);
    });
  });

  test('copyWith replaces only the named field', () {
    const base = DeleteChaptersSettings();
    final next = base.copyWith(deleteWhileReading: 5);
    expect(next.deleteWhileReading, 5);
    expect(next.deleteManuallyMarkedRead, isFalse);
    expect(next.deleteWithBookmark, isFalse);
  });
}
