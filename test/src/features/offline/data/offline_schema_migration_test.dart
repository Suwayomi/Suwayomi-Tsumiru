// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tsumiru/src/features/offline/data/offline_database.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
  // Use a temp directory so each test run gets a fresh file and close/reopen
  // semantics are real (not in-memory).
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('offline_migration_test_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test(
      'v2 schema persists keep-rule + pinned + downloadedAt across close/reopen',
      () async {
    final dbPath = p.join(tmp.path, 'test.db');

    // Open, populate, close.
    {
      final db = testOfflineDatabaseFile(dbPath);
      await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
      await db.upsertChapterMetadata(
        id: 10,
        mangaId: 1,
        name: 'c',
        chapterIndex: 1,
        isRead: false,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: 3,
        updatedAt: DateTime(2026),
      );
      await db.setKeepRule(1, OfflineKeepRule.allUnread, 7);
      await db.setChapterPinned(10, true);
      await db.setChapterDeviceState(10, OfflineDeviceState.downloaded,
          bytes: 512, downloadedAt: DateTime(2026, 3, 15));
      await db.close();
    }

    // Reopen and assert the v2 columns persisted with the values we wrote.
    {
      final db = testOfflineDatabaseFile(dbPath);
      final m = await (db.select(db.offlineMangas)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(m.keepRule, OfflineKeepRule.allUnread);
      expect(m.keepUnreadCount, 7);

      final c = await (db.select(db.offlineChapters)
            ..where((t) => t.id.equals(10)))
          .getSingle();
      expect(c.pinned, true);
      expect(c.downloadedAt, DateTime(2026, 3, 15));
      await db.close();
    }
  });
}
