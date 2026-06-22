// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;

  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  test('opens at schema version 3', () {
    expect(db.schemaVersion, 3);
  });

  test('inserts and reads a manga', () async {
    await db.into(db.offlineMangas).insert(
          OfflineMangasCompanion.insert(
            id: const Value(117),
            title: 'Solo Leveling',
            updatedAt: DateTime.utc(2026),
          ),
        );
    final rows = await db.select(db.offlineMangas).get();
    expect(rows.single.title, 'Solo Leveling');
  });

  test('chapter deviceState defaults to none and round-trips an enum', () async {
    await db.into(db.offlineChapters).insert(
          OfflineChaptersCompanion.insert(
            id: const Value(2000),
            mangaId: 552,
            name: 'Chapter 79',
            chapterIndex: 79,
            updatedAt: DateTime.utc(2026),
          ),
        );
    final c = await (db.select(db.offlineChapters)
          ..where((t) => t.id.equals(2000)))
        .getSingle();
    expect(c.deviceState, OfflineDeviceState.none);

    await (db.update(db.offlineChapters)..where((t) => t.id.equals(2000)))
        .write(const OfflineChaptersCompanion(
            deviceState: Value(OfflineDeviceState.downloaded)));
    final c2 = await (db.select(db.offlineChapters)
          ..where((t) => t.id.equals(2000)))
        .getSingle();
    expect(c2.deviceState, OfflineDeviceState.downloaded);
  });

  test('offline page maps (chapterId,pageIndex) -> relative path', () async {
    await db.into(db.offlinePages).insert(
          OfflinePagesCompanion.insert(
            chapterId: 2000,
            pageIndex: 0,
            relativePath: '552/2000/000.jpg',
          ),
        );
    final rows = await (db.select(db.offlinePages)
          ..where((t) => t.chapterId.equals(2000)))
        .get();
    expect(rows.single.relativePath, '552/2000/000.jpg');
  });
}
