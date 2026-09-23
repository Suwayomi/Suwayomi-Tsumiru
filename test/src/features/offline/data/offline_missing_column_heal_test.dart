// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// A device that ran an unmerged build can record a schema version whose step
// on main added columns it never got (two branches both claimed v17). Seen in
// the field: offline_categories at v17 without is_default_category/auto_add,
// so every category read threw "Null check operator used on a null value".

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tsumiru/src/utils/crash/diagnostics.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
  late Directory tmp;
  late String dbPath;
  late List<String> lines;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('offline_heal_test_');
    dbPath = p.join(tmp.path, 'catalog.sqlite');
    lines = [];
    setDiagnosticSink(lines.add);
  });
  tearDown(() async {
    setDiagnosticSink(null);
    await tmp.delete(recursive: true);
  });

  /// Rebuilds offline_categories with the exact DDL found on the device (no
  /// is_default_category / auto_add) while keeping the current user_version.
  Future<void> seedDeviceLikeCatalogue() async {
    final db = testOfflineDatabaseFile(dbPath);
    await db.customStatement('DROP TABLE offline_categories');
    await db.customStatement(
      'CREATE TABLE "offline_categories" ("id" INTEGER NOT NULL, '
      '"name" TEXT NOT NULL, "sort_order" INTEGER NOT NULL DEFAULT 0, '
      '"is_hidden" INTEGER NOT NULL DEFAULT 0 CHECK ("is_hidden" IN (0, 1)), '
      'PRIMARY KEY ("id"))',
    );
    await db.customStatement(
      "INSERT INTO offline_categories (id, name, sort_order) VALUES "
      "(0, 'Default', 0), (1, 'Reading', 1)",
    );
    await db.close();
  }

  test('an existing catalogue missing declared columns is healed on open, '
      'with the default category backfilled', () async {
    await seedDeviceLikeCatalogue();
    lines.clear();

    final db = testOfflineDatabaseFile(dbPath);
    final categories = await db.allOfflineCategories();
    await db.close();

    expect(
      {for (final c in categories) c.id: c.isDefaultCategory},
      {0: true, 1: false},
    );
    expect(categories.every((c) => !c.autoAdd), isTrue);
    expect(
      lines.join(),
      contains(
        'healed-missing-column '
        'offline_categories.is_default_category',
      ),
    );
    expect(
      lines.join(),
      contains(
        'healed-missing-column '
        'offline_categories.auto_add',
      ),
    );
  });

  test('a healed catalogue is not touched again on the next open', () async {
    await seedDeviceLikeCatalogue();
    final first = testOfflineDatabaseFile(dbPath);
    await first.allOfflineCategories();
    await first.close();
    lines.clear();

    final db = testOfflineDatabaseFile(dbPath);
    await db.allOfflineCategories();
    await db.close();
    expect(lines, isEmpty);
  });

  test('a healthy catalogue opens with no heal and no log line', () async {
    final db = testOfflineDatabaseFile(dbPath);
    await db.upsertCategory(1, 'Reading', 0, isHidden: false);
    await db.close();
    lines.clear();

    final reopened = testOfflineDatabaseFile(dbPath);
    expect(await reopened.allOfflineCategories(), hasLength(1));
    await reopened.close();
    expect(lines, isEmpty);
  });
}
