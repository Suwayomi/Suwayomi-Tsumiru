// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:drift/drift.dart';
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

  test('migration is idempotent: re-adding existing columns does not crash',
      () async {
    final dbPath = p.join(tmp.path, 'test.db');

    // Create a fresh DB (all current columns present), then force the recorded
    // schema version back to 1 — exactly the inconsistent state a device left
    // by an intermediate/dev build can end up in (column present, old version).
    {
      final db = testOfflineDatabaseFile(dbPath);
      await db.customStatement('PRAGMA user_version = 1');
      await db.close();
    }

    // Reopen: onUpgrade(from: 1) runs every `from < N` branch and would re-add
    // already-present columns. The idempotent guard must skip them instead of
    // throwing "duplicate column" — so the DB opens and is usable.
    {
      final db = testOfflineDatabaseFile(dbPath);
      await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
      expect(await db.select(db.offlineChapters).get(), isEmpty);
      await db.close();
    }
  });

  test('v15 readStateManual persists across close/reopen', () async {
    final dbPath = p.join(tmp.path, 'test.db');

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
      await db.setChapterReadState(10, true, manual: true);
      await db.close();
    }

    {
      final db = testOfflineDatabaseFile(dbPath);
      final c = await (db.select(db.offlineChapters)
            ..where((t) => t.id.equals(10)))
          .getSingle();
      expect(c.readStateManual, true);
      await db.close();
    }
  });

  Future<bool> hasIndex(OfflineDatabase db, String name) async {
    final rows = await db
        .customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='index' AND name=?",
          variables: [Variable<String>(name)],
        )
        .get();
    return rows.isNotEmpty;
  }

  test('v15 creates idx_offline_chapter_device_state on a fresh database',
      () async {
    final db = testOfflineDatabaseFile(p.join(tmp.path, 'test.db'));
    expect(await hasIndex(db, 'idx_offline_chapter_device_state'), isTrue);
    await db.close();
  });

  test(
      'v15 creates idx_offline_chapter_device_state when upgrading from an '
      'older on-disk database', () async {
    final dbPath = p.join(tmp.path, 'test.db');

    // Open at the current schema (creating the index via onCreate), then
    // force the recorded version back down — the same inconsistent state an
    // existing install upgrading from before this index existed would be in.
    {
      final db = testOfflineDatabaseFile(dbPath);
      await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
      await db.customStatement('DROP INDEX idx_offline_chapter_device_state');
      await db.customStatement('PRAGMA user_version = 14');
      await db.close();
    }

    {
      final db = testOfflineDatabaseFile(dbPath);
      // Touch the db to force it open (drift opens lazily).
      await db.select(db.offlineMangas).get();
      expect(await hasIndex(db, 'idx_offline_chapter_device_state'), isTrue);
      await db.close();
    }
  });

  test(
      'an upgrade from < 10 does not clobber a synced_is_read value an '
      'interim build already set (no more duplicate unconditional backfill)',
      () async {
    final dbPath = p.join(tmp.path, 'test.db');

    // Simulates an interim/dev build: the column already physically exists
    // (created by a prior run at the CURRENT schema) but the recorded version
    // is forced back below 10 -- the exact inconsistent state the surrounding
    // migration's own comments call out repeatedly. synced_is_read is set to
    // something that deliberately does NOT match is_read, standing in for a
    // real unsettled local correction this device is tracking.
    {
      final db = testOfflineDatabaseFile(dbPath);
      await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
      await db.upsertChapterMetadata(
        id: 10,
        mangaId: 1,
        name: 'c',
        chapterIndex: 1,
        isRead: true,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: 1,
        updatedAt: DateTime(2026),
      );
      await db.customStatement(
        'UPDATE offline_chapters SET synced_is_read = 0 WHERE id = 10',
      );
      await db.customStatement('PRAGMA user_version = 9');
      await db.close();
    }

    {
      final db = testOfflineDatabaseFile(dbPath);
      final c = await (db.select(db.offlineChapters)
            ..where((t) => t.id.equals(10)))
          .getSingle();
      expect(c.isRead, isTrue);
      expect(c.syncedIsRead, isFalse,
          reason: 'the from<12 guard already decided to preserve this value '
              'because the column existed; a later duplicate unconditional '
              'UPDATE synced_is_read = is_read must not override that');
      await db.close();
    }
  });

  test('v4 lastReadAt persists across close/reopen', () async {
    final dbPath = p.join(tmp.path, 'test.db');

    {
      final db = testOfflineDatabaseFile(dbPath);
      await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
      await db.upsertChapterMetadata(
        id: 10,
        mangaId: 1,
        name: 'c',
        chapterIndex: 1,
        isRead: true,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: 3,
        updatedAt: DateTime(2026),
        lastReadAt: '1700000000000',
      );
      await db.close();
    }

    {
      final db = testOfflineDatabaseFile(dbPath);
      final c = await (db.select(db.offlineChapters)
            ..where((t) => t.id.equals(10)))
          .getSingle();
      expect(c.lastReadAt, '1700000000000');
      expect(await db.lastReadAtByManga(), {1: '1700000000000'});
      await db.close();
    }
  });
}
