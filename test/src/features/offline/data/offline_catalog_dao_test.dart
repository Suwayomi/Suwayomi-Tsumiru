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
  }) =>
      db.upsertChapterMetadata(
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
    await db.setChapterDeviceState(2000, OfflineDeviceState.downloaded,
        bytes: 9999);

    // A later metadata down-sync (server now says isRead=true) must NOT reset
    // deviceState/bytes.
    await seedChapter(isRead: true, lastPageRead: 5);

    final c = (await db.chaptersForManga(552)).single;
    expect(c.deviceState, OfflineDeviceState.downloaded, reason: 'preserved');
    expect(c.bytes, 9999, reason: 'preserved');
    expect(c.isRead, isTrue, reason: 'server field updated');
    expect(c.lastPageRead, 5);
  });

  test('metadata re-sync PRESERVES a manga cover path', () async {
    await db.upsertMangaMetadata(
        id: 552, title: 'A', updatedAt: DateTime.utc(2026));
    await db.setMangaCoverPath(552, 'covers/552.jpg');
    await db.upsertMangaMetadata(
        id: 552, title: 'A (renamed)', updatedAt: DateTime.utc(2026, 2));

    final m = (await db.libraryManga()).single;
    expect(m.thumbnailRelPath, 'covers/552.jpg', reason: 'preserved');
    expect(m.title, 'A (renamed)', reason: 'server field updated');
  });

  test('downloadedChaptersForManga filters by device state', () async {
    await seedChapter(id: 1, mangaId: 7);
    await seedChapter(id: 2, mangaId: 7);
    await db.setChapterDeviceState(1, OfflineDeviceState.downloaded);
    final dl = await db.downloadedChaptersForManga(7);
    expect(dl.map((c) => c.id), [1]);
  });

  test('chaptersForManga is ordered by chapterIndex', () async {
    await db.upsertChapterMetadata(
        id: 10, mangaId: 7, name: 'b', chapterIndex: 2, isRead: false,
        lastPageRead: 0, isBookmarked: false, serverIsDownloaded: false,
        pageCount: 1, updatedAt: DateTime.utc(2026));
    await db.upsertChapterMetadata(
        id: 11, mangaId: 7, name: 'a', chapterIndex: 1, isRead: false,
        lastPageRead: 0, isBookmarked: false, serverIsDownloaded: false,
        pageCount: 1, updatedAt: DateTime.utc(2026));
    final list = await db.chaptersForManga(7);
    expect(list.map((c) => c.id), [11, 10]);
  });

  test('lastReadAtByManga takes the max and drops unread mangas', () async {
    // Manga 7: two read chapters — the newer timestamp wins.
    await db.upsertChapterMetadata(
        id: 1, mangaId: 7, name: 'a', chapterIndex: 1, isRead: true,
        lastPageRead: 0, isBookmarked: false, serverIsDownloaded: false,
        pageCount: 1, updatedAt: DateTime.utc(2026),
        lastReadAt: '1700000000000');
    await db.upsertChapterMetadata(
        id: 2, mangaId: 7, name: 'b', chapterIndex: 2, isRead: true,
        lastPageRead: 0, isBookmarked: false, serverIsDownloaded: false,
        pageCount: 1, updatedAt: DateTime.utc(2026),
        lastReadAt: '1800000000000');
    // Manga 8: never read (server default '0') — excluded.
    await db.upsertChapterMetadata(
        id: 3, mangaId: 8, name: 'c', chapterIndex: 1, isRead: false,
        lastPageRead: 0, isBookmarked: false, serverIsDownloaded: false,
        pageCount: 1, updatedAt: DateTime.utc(2026), lastReadAt: '0');
    // Manga 9: no lastReadAt supplied at all (NULL) — excluded.
    await db.upsertChapterMetadata(
        id: 4, mangaId: 9, name: 'd', chapterIndex: 1, isRead: false,
        lastPageRead: 0, isBookmarked: false, serverIsDownloaded: false,
        pageCount: 1, updatedAt: DateTime.utc(2026));

    expect(await db.lastReadAtByManga(), {7: '1800000000000'});
  });

  test('totalDownloadedBytes sums bytes', () async {
    await seedChapter(id: 1, mangaId: 7);
    await seedChapter(id: 2, mangaId: 7);
    await db.setChapterDeviceState(1, OfflineDeviceState.downloaded, bytes: 100);
    await db.setChapterDeviceState(2, OfflineDeviceState.downloaded, bytes: 250);
    expect(await db.totalDownloadedBytes(), 350);
  });
}
