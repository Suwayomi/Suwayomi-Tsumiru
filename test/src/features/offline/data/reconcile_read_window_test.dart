// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/reconcile_logic.dart';
import 'package:tsumiru/src/features/offline/data/reconcile_types.dart';

OfflineChapter _ch(int id, {bool isRead = false, String? readAt}) =>
    OfflineChapter(
      id: id,
      mangaId: 1,
      name: 'c$id',
      chapterIndex: id,
      isRead: isRead,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: true,
      deviceState: OfflineDeviceState.downloaded,
      pageCount: 1,
      bytes: 100,
      pinned: false,
      downloadedAt: DateTime(2026, 1, 1),
      progressDirty: false,
      bookmarkDirty: false,
      readStateDirty: false,
      readStateManual: false,
      syncedIsRead: false,
      lastReadAt: readAt,
      updatedAt: DateTime(2026),
      downloadGeneration: 0,
    );

void main() {
  group('readChaptersInDeleteWindow', () {
    test('a window of one keeps only the most recently read chapter', () {
      final chapters = [
        _ch(1, isRead: true),
        _ch(2, isRead: true),
        _ch(3, isRead: true),
        _ch(4),
      ];

      expect(readChaptersInDeleteWindow(chapters, 2), {3});
    });

    test('a wider window keeps more of the recently read chapters', () {
      final chapters = [
        _ch(1, isRead: true),
        _ch(2, isRead: true),
        _ch(3, isRead: true),
        _ch(4),
      ];

      expect(readChaptersInDeleteWindow(chapters, 4), {1, 2, 3});
    });

    test('a window of none keeps nothing', () {
      expect(readChaptersInDeleteWindow([_ch(1, isRead: true)], 1), isEmpty);
    });

    test('the setting being off keeps nothing', () {
      expect(readChaptersInDeleteWindow([_ch(1, isRead: true)], 0), isEmpty);
    });

    test('dipping back to an early chapter keeps that one, not the furthest',
        () {
      final chapters = [
        _ch(1, isRead: true, readAt: '2000'),
        _ch(2, isRead: true, readAt: '3000'),
        _ch(50, isRead: true, readAt: '1000'),
      ];

      expect(readChaptersInDeleteWindow(chapters, 2), {2},
          reason: 'chapter 2 was read most recently even though 50 is further '
              'along');
    });

    test('chapters with no read timestamp fall back to reading order', () {
      final chapters = [_ch(1, isRead: true), _ch(9, isRead: true)];

      expect(readChaptersInDeleteWindow(chapters, 2), {9});
    });
  });

  test('a chapter read on another device survives the keep rule (#325)', () {
    final chapters = [
      _ch(1, isRead: true),
      _ch(2, isRead: true),
      _ch(3),
      _ch(4),
    ];
    // "keep 2 unread" wants only the unread ones, and nothing was read in this
    // session — which is exactly how the other device's sync wiped the lot.
    final desired = desiredChapterIds(chapters, OfflineKeepRule.nUnread, 2);

    final r = applySafetyNets(
      downloaded: chapters,
      desired: desired,
      nets: SafetyNetConfig.off,
      now: DateTime(2026, 3, 1),
      protected: readChaptersInDeleteWindow(chapters, 2),
    );

    expect(r.evict, {1},
        reason: 'chapter 2 is inside the keep window and must survive '
            'regardless of which device read it');
  });
}
