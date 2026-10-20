// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  Future<void> seedChapter({
    int id = 2000,
    int mangaId = 552,
    bool isRead = false,
    int lastPageRead = 0,
  }) => db.upsertChapterMetadata(
    id: id,
    mangaId: mangaId,
    name: 'Chapter',
    chapterIndex: 79,
    isRead: isRead,
    lastPageRead: lastPageRead,
    isBookmarked: false,
    serverIsDownloaded: true,
    pageCount: 33,
    updatedAt: DateTime.utc(2026),
  );

  test('metadata re-sync PRESERVES device-managed chapter fields', () async {
    await seedChapter();
    // Device marks it downloaded with a byte size.
    await db.setChapterDeviceState(
      2000,
      OfflineDeviceState.downloaded,
      bytes: 9999,
    );

    // A later metadata down-sync (server now says isRead=true) must NOT reset
    // deviceState/bytes.
    await seedChapter(isRead: true, lastPageRead: 5);

    final c = (await db.chaptersForManga(552)).single;
    expect(c.deviceState, OfflineDeviceState.downloaded, reason: 'preserved');
    expect(c.bytes, 9999, reason: 'preserved');
    expect(c.isRead, isTrue, reason: 'server field updated');
    expect(c.lastPageRead, 5);
  });
}
