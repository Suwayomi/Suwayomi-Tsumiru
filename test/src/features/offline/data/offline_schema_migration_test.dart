// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

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

  test('keep-rule, pinned, downloadedAt and readStateManual persist '
      'across close/reopen', () async {
    final dbPath = p.join(tmp.path, 'test.db');

    // Open, populate, close.
    {
      final db = testOfflineDatabaseFile(dbPath);
      await db.upsertMangaMetadata(
        id: 1,
        title: 'M',
        updatedAt: DateTime(2026),
      );
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
      await db.setChapterDeviceState(
        10,
        OfflineDeviceState.downloaded,
        bytes: 512,
        downloadedAt: DateTime(2026, 3, 15),
      );
      await db.setChapterReadState(10, true, manual: true);
      await db.close();
    }

    // Reopen and assert every column persisted with the value we wrote.
    {
      final db = testOfflineDatabaseFile(dbPath);
      final m = await (db.select(
        db.offlineMangas,
      )..where((t) => t.id.equals(1))).getSingle();
      expect(m.keepRule, OfflineKeepRule.allUnread);
      expect(m.keepUnreadCount, 7);

      final c = await (db.select(
        db.offlineChapters,
      )..where((t) => t.id.equals(10))).getSingle();
      expect(c.pinned, true);
      expect(c.downloadedAt, DateTime(2026, 3, 15));
      expect(c.readStateManual, true);
      await db.setChapterDeviceState(
        10,
        OfflineDeviceState.error,
        failureReason: 'Source not installed: 687150405919946955',
      );
      await db.close();
    }
    {
      final db = testOfflineDatabaseFile(dbPath);
      expect(
        (await db.chapterById(10))!.failureReason,
        'Source not installed: 687150405919946955',
      );
      await db.setChapterDeviceState(10, OfflineDeviceState.queued);
      expect((await db.chapterById(10))!.failureReason, isNull);
      await db.close();
    }
  });

  test('upgrades are idempotent and v18 columns land on a v17 file', () async {
    // Idempotence: a fresh DB whose recorded version was pushed back to 1
    // (column present, old version — the state an intermediate build can
    // leave) must reopen without re-adding columns.
    final idempotentPath = p.join(tmp.path, 'idempotent.db');
    {
      final db = testOfflineDatabaseFile(idempotentPath);
      await db.customStatement('PRAGMA user_version = 1');
      await db.close();
    }
    {
      final db = testOfflineDatabaseFile(idempotentPath);
      await db.upsertMangaMetadata(
        id: 1,
        title: 'M',
        updatedAt: DateTime(2026),
      );
      expect(await db.select(db.offlineChapters).get(), isEmpty);
      await db.close();
    }

    // v18: a real v17 install gains the sort/date columns, null to start and
    // genuinely usable afterwards.
    final upgradePath = p.join(tmp.path, 'upgrade.db');
    {
      final db = testOfflineDatabaseFile(upgradePath);
      await db.upsertMangaMetadata(
        id: 1,
        title: 'M',
        updatedAt: DateTime(2026),
      );
      await db.upsertChapterMetadata(
        id: 10,
        mangaId: 1,
        name: 'c',
        chapterIndex: 1,
        isRead: false,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: 1,
        updatedAt: DateTime(2026),
      );
      await db.customStatement(
        'ALTER TABLE offline_chapters DROP COLUMN failure_reason',
      );
      await db.customStatement('PRAGMA user_version = 17');
      await db.close();
    }
    {
      final db = testOfflineDatabaseFile(upgradePath);
      final m = await (db.select(
        db.offlineMangas,
      )..where((t) => t.id.equals(1))).getSingle();
      expect(m.chapterSortMode, null);
      final c = await (db.select(
        db.offlineChapters,
      )..where((t) => t.id.equals(10))).getSingle();
      expect(c.uploadDate, null);
      expect(c.fetchedAt, null);
      expect(c.failureReason, isNull);

      await db.upsertMangaMetadata(
        id: 1,
        title: 'M',
        updatedAt: DateTime(2026),
        chapterSortMode: ChapterSortAxis.uploadedAt,
      );
      await db.upsertChapterMetadata(
        id: 10,
        mangaId: 1,
        name: 'c',
        chapterIndex: 1,
        isRead: false,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: 1,
        updatedAt: DateTime(2026),
        uploadDate: '1700000000000',
        fetchedAt: '1700000001000',
      );
      final m2 = await (db.select(
        db.offlineMangas,
      )..where((t) => t.id.equals(1))).getSingle();
      expect(m2.chapterSortMode, ChapterSortAxis.uploadedAt);
      final c2 = await (db.select(
        db.offlineChapters,
      )..where((t) => t.id.equals(10))).getSingle();
      expect(c2.uploadDate, '1700000000000');
      expect(c2.fetchedAt, '1700000001000');
      await db.close();
    }
  });
}
