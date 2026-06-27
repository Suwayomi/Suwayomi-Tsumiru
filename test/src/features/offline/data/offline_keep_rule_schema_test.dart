// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  test('opens at schema version 4', () {
    expect(db.schemaVersion, 4);
  });

  test('keepRule defaults to off, keepUnreadCount to 3; setKeepRule persists',
      () async {
    await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
    var m = await (db.select(db.offlineMangas)
          ..where((t) => t.id.equals(1)))
        .getSingle();
    expect(m.keepRule, OfflineKeepRule.off);
    expect(m.keepUnreadCount, 3);

    await db.setKeepRule(1, OfflineKeepRule.nUnread, 5);
    m = await (db.select(db.offlineMangas)..where((t) => t.id.equals(1)))
        .getSingle();
    expect(m.keepRule, OfflineKeepRule.nUnread);
    expect(m.keepUnreadCount, 5);
  });

  test(
      'pinned defaults false; setChapterPinned persists; downloadedAt stamps on download',
      () async {
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
    var c = await (db.select(db.offlineChapters)
          ..where((t) => t.id.equals(10)))
        .getSingle();
    expect(c.pinned, false);
    expect(c.downloadedAt, isNull);

    await db.setChapterPinned(10, true);
    await db.setChapterDeviceState(10, OfflineDeviceState.downloaded,
        bytes: 100, downloadedAt: DateTime(2026, 2, 2));
    c = await (db.select(db.offlineChapters)..where((t) => t.id.equals(10)))
        .getSingle();
    expect(c.pinned, true);
    expect(c.downloadedAt, DateTime(2026, 2, 2));
  });
}
