// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_dto_mappers.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  Future<OfflineChapter> upsert({
    required int id,
    double? number,
    String? scanlator,
  }) async {
    await db.upsertChapterMetadata(
      id: id,
      mangaId: 1,
      name: 'c$id',
      chapterIndex: id,
      isRead: false,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: false,
      pageCount: 3,
      updatedAt: DateTime(2026),
      chapterNumber: number,
      scanlator: scanlator,
    );
    return (db.select(db.offlineChapters)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  test('chapterNumber and scanlator persist through the upsert', () async {
    final c = await upsert(id: 10, number: 9.5, scanlator: 'Nyx Scans');
    expect((c.chapterNumber, c.scanlator), (9.5, 'Nyx Scans'));
  });

  test('mapper prefers the real number and carries the scanlator', () async {
    final c = await upsert(id: 11, number: 2, scanlator: 'A');
    final dto = offlineChapterToDto(c);
    expect((dto.chapterNumber, dto.scanlator, dto.sourceOrder), (2.0, 'A', 11));
  });

  test('mapper falls back to the index for pre-v9 rows (null number)',
      () async {
    final c = await upsert(id: 12);
    final dto = offlineChapterToDto(c);
    expect((dto.chapterNumber, dto.scanlator), (12.0, null));
  });

  test('omitting the fields on a later upsert preserves synced values',
      () async {
    await upsert(id: 13, number: 4, scanlator: 'B');
    final c = await upsert(id: 13); // e.g. a caller without the new fields
    expect((c.chapterNumber, c.scanlator), (4.0, 'B'));
  });

  group('v8 -> v9 upgrade (real fixture, columns genuinely absent)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('offline_v9_migration_');
    });
    tearDown(() => tmp.delete(recursive: true));

    test('adds the columns, preserves rows, lands on version 16', () async {
      final dbPath = p.join(tmp.path, 'test.db');

      // Build a genuine v8 file: the chapters table WITHOUT the new columns,
      // one row, user_version stamped 8. Raw sqlite so drift can't migrate it.
      final v8 = raw.sqlite3.open(dbPath);
      v8.execute('''
        CREATE TABLE offline_chapters (
          id INTEGER NOT NULL PRIMARY KEY,
          manga_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          chapter_index INTEGER NOT NULL,
          is_read INTEGER NOT NULL DEFAULT 0,
          last_page_read INTEGER NOT NULL DEFAULT 0,
          is_bookmarked INTEGER NOT NULL DEFAULT 0,
          server_is_downloaded INTEGER NOT NULL DEFAULT 0,
          device_state TEXT NOT NULL DEFAULT 'none',
          page_count INTEGER NOT NULL DEFAULT 0,
          bytes INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL,
          pinned INTEGER NOT NULL DEFAULT 0,
          downloaded_at INTEGER,
          progress_dirty INTEGER NOT NULL DEFAULT 0,
          bookmark_dirty INTEGER NOT NULL DEFAULT 0,
          read_state_dirty INTEGER NOT NULL DEFAULT 0,
          last_read_at TEXT,
          download_generation INTEGER NOT NULL DEFAULT 0
        );
      ''');
      v8.execute(
          "INSERT INTO offline_chapters (id, manga_id, name, chapter_index, "
          "is_read, updated_at) VALUES (10, 1, 'c10', 9, 1, 0)");
      // A real v8 file always has the manga table too — the v10 step alters
      // it, so the fixture must carry it or the upgrade dies on ALTER.
      v8.execute('''
        CREATE TABLE offline_mangas (
          id INTEGER NOT NULL PRIMARY KEY,
          title TEXT NOT NULL,
          thumbnail_url TEXT,
          thumbnail_rel_path TEXT,
          updated_at INTEGER NOT NULL,
          keep_rule TEXT NOT NULL DEFAULT 'off',
          keep_unread_count INTEGER NOT NULL DEFAULT 3,
          source_id TEXT,
          source_name TEXT,
          source_lang TEXT,
          source_is_nsfw INTEGER NOT NULL DEFAULT 0,
          status TEXT,
          unread_count INTEGER NOT NULL DEFAULT 0,
          download_count INTEGER NOT NULL DEFAULT 0,
          bookmark_count INTEGER NOT NULL DEFAULT 0,
          in_library_at TEXT,
          latest_fetched_at TEXT,
          latest_uploaded_at TEXT,
          total_chapters INTEGER NOT NULL DEFAULT 0
        );
      ''');
      v8.execute(
          "INSERT INTO offline_mangas (id, title, updated_at, in_library_at) "
          "VALUES (1, 'M1', 0, '100')");
      v8.execute('PRAGMA user_version = 8');
      v8.dispose();

      final db = testOfflineDatabaseFile(dbPath);
      final c = await (db.select(db.offlineChapters)
            ..where((t) => t.id.equals(10)))
          .getSingle();
      // Old data survived; the new columns exist and read as null.
      expect((c.name, c.chapterIndex, c.isRead), ('c10', 9, true));
      expect((c.chapterNumber, c.scanlator), (null, null));
      final version = await db
          .customSelect('PRAGMA user_version')
          .getSingle()
          .then((r) => r.read<int>('user_version'));
      expect(version, 16);
      // v14 must create both category tables on an upgrade from before they
      // existed — onCreate only runs for fresh files.
      await db.upsertCategory(1, 'A', 0, isHidden: false);
      await db.replaceMangaCategories(1, [1]);
      expect((await db.categoriesForManga(1)).single.name, 'A');
      await db.close();
    });
  });
}
