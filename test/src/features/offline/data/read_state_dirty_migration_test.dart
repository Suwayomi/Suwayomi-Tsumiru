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
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('read_state_dirty_migration_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<void> seedRow(OfflineDatabase db, int id,
      {required bool isRead, required bool progressDirty}) async {
    await db.upsertChapterMetadata(
      id: id,
      mangaId: 1,
      name: 'c$id',
      chapterIndex: id,
      isRead: isRead,
      lastPageRead: isRead ? 0 : 5,
      isBookmarked: false,
      serverIsDownloaded: true,
      pageCount: 30,
      updatedAt: DateTime(2026),
    );
    // setChapterProgress marks progressDirty without touching isRead (isRead:
    // null), so we can arm the dirty flag independently of the read-state.
    if (progressDirty) {
      await db.setChapterProgress(id, lastPageRead: isRead ? 0 : 5);
    }
  }

  test('v6→v7 seeds readStateDirty only for progress-dirty completed reads',
      () async {
    final dbPath = p.join(tmp.path, 'test.db');

    // Create a v7 DB, seed the three classes, then rewind it to a v6 shape by
    // dropping the new column and forcing the recorded version back — exactly
    // the on-disk state a pre-upgrade device carries.
    {
      final db = testOfflineDatabaseFile(dbPath);
      await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
      // A: pending completed offline read (progressDirty + isRead) → carried.
      await seedRow(db, 1, isRead: true, progressDirty: true);
      // B: the stale class — position dirty but not read → stays position-only.
      await seedRow(db, 2, isRead: false, progressDirty: true);
      // C: clean server-read row → nothing pending, no read-state flag.
      await seedRow(db, 3, isRead: true, progressDirty: false);
      await db.customStatement(
          'ALTER TABLE offline_chapters DROP COLUMN read_state_dirty');
      await db.customStatement('PRAGMA user_version = 6');
      await db.close();
    }

    // Reopen: onUpgrade(6, 7) re-adds the column and runs the seed UPDATE.
    {
      final db = testOfflineDatabaseFile(dbPath);
      final a = (await db.chapterById(1))!;
      final b = (await db.chapterById(2))!;
      final c = (await db.chapterById(3))!;
      expect(a.readStateDirty, isTrue, reason: 'pending read carried over');
      expect(b.readStateDirty, isFalse, reason: 'stale class neutralized');
      expect(c.readStateDirty, isFalse, reason: 'clean row untouched');
      // Position dirtiness is untouched by the split.
      expect(a.progressDirty, isTrue);
      expect(b.progressDirty, isTrue);
      await db.close();
    }
  });
}
