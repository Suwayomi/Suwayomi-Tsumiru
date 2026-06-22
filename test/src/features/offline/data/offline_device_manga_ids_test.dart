// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../../helpers/offline_test_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  test('returns manga ids with at least one downloaded chapter', () async {
    await db.upsertChapterMetadata(id: 1, mangaId: 10, name: 'a', chapterIndex: 1,
      isRead: false, lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
      pageCount: 1, updatedAt: DateTime(2026));
    await db.upsertChapterMetadata(id: 2, mangaId: 20, name: 'b', chapterIndex: 1,
      isRead: false, lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
      pageCount: 1, updatedAt: DateTime(2026));
    await db.setChapterDeviceState(1, OfflineDeviceState.downloaded, bytes: 5);
    expect(await db.mangaIdsWithDeviceDownloads(), {10});
  });
}
