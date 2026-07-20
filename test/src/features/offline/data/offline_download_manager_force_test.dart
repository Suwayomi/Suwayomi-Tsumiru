// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_manager.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store.dart';

import '../../../../helpers/offline_test_db.dart';

class _FakeStore implements OfflinePageStore {
  @override
  Future<({String relPath, int bytes})> writePage(
          int m, int c, int i, List<int> b, String e) async =>
      (relPath: '$m/$c/$i.$e', bytes: b.length);
  @override
  Future<void> deleteChapter(int m, int c) async {}
  @override
  Future<int> chapterBytes(int m, int c) async => 0;
  @override
  Future<void> clearAll() async {}
}

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  OfflineChapter chap(bool serverDl) => OfflineChapter(
        id: 1,
        mangaId: 1,
        name: 'c',
        chapterIndex: 1,
        isRead: false,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: serverDl,
        deviceState: OfflineDeviceState.none,
        pageCount: 1,
        bytes: 0,
        pinned: false,
        downloadedAt: null,
        progressDirty: false,
        bookmarkDirty: false,
        readStateDirty: false,
        updatedAt: DateTime(2026),
        downloadGeneration: 0,
      );

  OfflineDownloadManager manager() => OfflineDownloadManager(
        db: db,
        store: _FakeStore(),
        fetchPageUrls: (id) async => ['/api/v1/x/0'],
        fetchBytes: (u) async => (bytes: [1, 2, 3], ext: 'jpg'),
      );

  test(
      'downloadChapter still refuses a not-server-downloaded chapter by default',
      () async {
    await expectLater(manager().downloadChapter(chap(false)), throwsStateError);
  });

  test(
      'downloadChapter(force: true) downloads despite serverIsDownloaded=false',
      () async {
    await db.upsertChapterMetadata(
        id: 1,
        mangaId: 1,
        name: 'c',
        chapterIndex: 1,
        isRead: false,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: false,
        pageCount: 1,
        updatedAt: DateTime(2026));
    await manager().downloadChapter(chap(false), force: true);
    final c = await (db.select(db.offlineChapters)
          ..where((t) => t.id.equals(1)))
        .getSingle();
    expect(c.deviceState, OfflineDeviceState.downloaded);
  });
}
