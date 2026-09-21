// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:tsumiru/src/features/offline/data/account_catalogue_recovery_io.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_recovery.dart';

void main() {
  late Directory root;
  late String source;
  late String target;
  setUp(() {
    root = Directory.systemTemp.createTempSync('catalogue-recovery-');
    source = p.join(root.path, 'old.sqlite');
    target = p.join(root.path, 'new.sqlite');
    for (final path in [source, target]) {
      final db = sqlite3.open(path);
      db.execute(
        'CREATE TABLE offline_chapters (id INTEGER PRIMARY KEY, manga_id INTEGER NOT NULL, name TEXT NOT NULL, is_read INTEGER NOT NULL, last_page_read INTEGER NOT NULL, is_bookmarked INTEGER NOT NULL, progress_dirty INTEGER NOT NULL DEFAULT 0, read_state_dirty INTEGER NOT NULL DEFAULT 0, bookmark_dirty INTEGER NOT NULL DEFAULT 0, read_state_manual INTEGER NOT NULL DEFAULT 0, synced_is_read INTEGER NOT NULL DEFAULT 0)',
      );
      db.execute(
        "INSERT INTO offline_chapters (id,manga_id,name,is_read,last_page_read,is_bookmarked) VALUES (7,1,'Chapter 7',0,2,0)",
      );
      db.close();
    }
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('changed progress invalidates a saved recovery choice', () async {
    final original = sqlite3.open(source);
    original.execute('UPDATE offline_chapters SET last_page_read=112');
    original.close();
    await reconcileAccountCatalogues(source, target, choices: {7: false});
    final changed = sqlite3.open(target);
    changed.execute('UPDATE offline_chapters SET last_page_read=3');
    changed.close();
    await expectLater(
      reconcileAccountCatalogues(source, target),
      throwsA(isA<AccountStorageProgressConflict>()),
    );
  });

  test('imports source-only rows and preserves destination-only rows', () async {
    for (final pair in [(source, 8), (target, 9)]) {
      final db = sqlite3.open(pair.$1);
      db.execute(
        "INSERT INTO offline_chapters (id,manga_id,name,is_read,last_page_read,is_bookmarked) VALUES (?,1,'New',0,0,0)",
        [pair.$2],
      );
      db.close();
    }
    await reconcileAccountCatalogues(source, target);
    final db = sqlite3.open(target);
    expect(
      db
          .select('SELECT id FROM offline_chapters ORDER BY id')
          .map((r) => r['id']),
      [7, 8, 9],
    );
    db.close();
    expect(File('$target.legacy-recovery-backup').existsSync(), isTrue);
    expect(File('$target.recovery-backup').existsSync(), isTrue);
  });

  test(
    'conflicting progress stays untouched until explicitly resolved',
    () async {
      final old = sqlite3.open(source);
      old.execute(
        'UPDATE offline_chapters SET last_page_read=112,progress_dirty=1',
      );
      old.close();
      await expectLater(
        reconcileAccountCatalogues(source, target),
        throwsA(
          isA<AccountStorageProgressConflict>()
              .having(
                (e) => e.conflicts.single.originalPage,
                'original page',
                112,
              )
              .having((e) => e.conflicts.single.currentPage, 'current page', 2),
        ),
      );
      final before = sqlite3.open(target);
      expect(
        before
            .select('SELECT last_page_read FROM offline_chapters')
            .single
            .values
            .single,
        2,
      );
      before.close();
      await reconcileAccountCatalogues(source, target, choices: {7: true});
      final after = sqlite3.open(target);
      expect(
        after
            .select(
              'SELECT last_page_read,progress_dirty FROM offline_chapters',
            )
            .single
            .values,
        [112, 1],
      );
      after.close();
      final backup = sqlite3.open('$target.recovery-backup');
      expect(
        backup
            .select('SELECT last_page_read FROM offline_chapters')
            .single
            .values
            .single,
        2,
      );
      backup.close();
    },
  );

  test('choosing current progress preserves a deliberate reset', () async {
    final old = sqlite3.open(source);
    old.execute(
      'UPDATE offline_chapters SET last_page_read=112,progress_dirty=1',
    );
    old.close();
    final current = sqlite3.open(target);
    current.execute(
      'UPDATE offline_chapters SET last_page_read=0,progress_dirty=1',
    );
    current.close();
    await reconcileAccountCatalogues(source, target, choices: {7: false});
    await reconcileAccountCatalogues(source, target);
    final after = sqlite3.open(target);
    expect(
      after
          .select('SELECT last_page_read,progress_dirty FROM offline_chapters')
          .single
          .values,
      [0, 1],
    );
    after.close();
  });
}
