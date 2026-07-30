// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_read_fallback.dart';

import '../../../../helpers/offline_test_db.dart';

// Removing a manga from the library must remove it from the offline library
// too, not leave a ghost row forever. Downloads survive removal; they just
// stop being library entries.
void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  Future<void> seed(int id, {String? inLibraryAt = '100'}) =>
      db.upsertMangaMetadata(
          id: id,
          title: 'M$id',
          updatedAt: DateTime(2026),
          inLibraryAt: inLibraryAt);

  test('removed manga without downloads is deleted outright', () async {
    await seed(1);
    await seed(2);
    await db.markNotInLibrary({1});
    await db.purgeRemovedLibraryManga();
    expect((await db.libraryManga()).map((m) => m.id), [1]);
    expect(await db.mangaById(2), isNull);
  });

  test('removed manga with a downloaded chapter keeps its row but leaves '
      'the offline library', () async {
    await seed(1);
    await seed(2);
    await db.upsertChapterMetadata(
        id: 21,
        mangaId: 2,
        name: 'c',
        chapterIndex: 1,
        isRead: false,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: 1,
        updatedAt: DateTime(2026));
    await db.setChapterDeviceState(21, OfflineDeviceState.downloaded, bytes: 5);

    await db.markNotInLibrary({1});
    await db.purgeRemovedLibraryManga();

    expect((await db.libraryManga()).map((m) => m.id), [1]);
    // Still present for the On-device tab and its downloaded pages.
    expect(await db.mangaById(2), isNotNull);
  });

  test('a manga back in the library set keeps its timestamp', () async {
    await seed(1);
    await db.markNotInLibrary({1});
    expect((await db.libraryManga()).map((m) => m.id), [1]);
  });

  test('Last Read offline uses the synced manga-level value when no chapter '
      'rows exist, and a newer local chapter read wins', () async {
    await db.upsertMangaMetadata(
        id: 1,
        title: 'A',
        updatedAt: DateTime(2026),
        inLibraryAt: '100',
        lastReadAt: '5000');
    await db.upsertMangaMetadata(
        id: 2,
        title: 'B',
        updatedAt: DateTime(2026),
        inLibraryAt: '100',
        lastReadAt: '1000');
    // Both need device files to appear in the offline library at all. Manga
    // 1's download carries no read timestamp, so its synced manga-level value
    // is the only signal; manga 2 was read locally after the last sync, so
    // its chapter row is newer than the snapshot and must win.
    for (final (cid, mid, ts) in [(11, 1, null), (21, 2, '9000')]) {
      await db.upsertChapterMetadata(
          id: cid,
          mangaId: mid,
          name: 'c',
          chapterIndex: 1,
          isRead: ts != null,
          lastPageRead: 0,
          isBookmarked: false,
          serverIsDownloaded: true,
          pageCount: 1,
          updatedAt: DateTime(2026),
          lastReadAt: ts);
      await db.setChapterDeviceState(
          cid, OfflineDeviceState.downloaded, bytes: 1);
    }

    final list = await libraryWithOfflineFallback(
        fetch: () async => throw const SocketException('unreachable'),
        db: db,
        offlineEnabled: true);
    final byId = {for (final m in list!) m.id: m};
    expect(byId[1]!.lastReadChapter?.lastReadAt, '5000');
    expect(byId[2]!.lastReadChapter?.lastReadAt, '9000');
  });
}
