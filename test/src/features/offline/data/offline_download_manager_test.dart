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

/// In-memory page store: records writes/deletes, no real file IO.
class _FakeStore implements OfflinePageStore {
  final Map<String, int> written = {};
  final List<int> deletedChapters = [];

  @override
  Future<({String relPath, int bytes})> writePage(int mangaId, int chapterId,
      int pageIndex, List<int> bytes, String ext) async {
    final rel =
        '$mangaId/$chapterId/${pageIndex.toString().padLeft(3, '0')}.$ext';
    written[rel] = bytes.length;
    return (relPath: rel, bytes: bytes.length);
  }

  @override
  Future<void> deleteChapter(int mangaId, int chapterId) async {
    deletedChapters.add(chapterId);
    written.removeWhere((k, _) => k.startsWith('$mangaId/$chapterId/'));
  }

  @override
  Future<int> chapterBytes(int mangaId, int chapterId) async => written.entries
      .where((e) => e.key.startsWith('$mangaId/$chapterId/'))
      .fold<int>(0, (s, e) => s + e.value);
  @override
  Future<void> clearAll() async {}
  @override
  Future<List<({int pageIndex, String relPath, int bytes})>> transferChapter(
    int fromMangaId,
    int fromChapterId,
    int toMangaId,
    int toChapterId, {
    required bool keepSource,
  }) =>
      throw UnimplementedError();
}

void main() {
  late OfflineDatabase db;
  late _FakeStore store;

  setUp(() {
    db = testOfflineDatabase();
    store = _FakeStore();
  });
  tearDown(() => db.close());

  Future<OfflineChapter> seedChapter({bool serverDownloaded = true}) async {
    await db.upsertChapterMetadata(
      id: 2000,
      mangaId: 552,
      name: 'Chapter 79',
      chapterIndex: 79,
      isRead: false,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: serverDownloaded,
      pageCount: 3,
      updatedAt: DateTime.utc(2026),
    );
    return (await db.chaptersForManga(552)).single;
  }

  OfflineDownloadManager managerWith({
    PageUrlsFetcher? urls,
    PageBytesFetcher? bytes,
  }) =>
      OfflineDownloadManager(
        db: db,
        store: store,
        fetchPageUrls: urls ?? (id) async => ['u0', 'u1', 'u2'],
        fetchBytes: bytes ?? (url) async => (bytes: [1, 2, 3], ext: 'jpg'),
      );

  test('downloadChapter stores all pages, records them, marks downloaded',
      () async {
    final chapter = await seedChapter();
    await managerWith().downloadChapter(chapter);

    expect(store.written.length, 3);
    final pages = await (db.select(db.offlinePages)
          ..where((t) => t.chapterId.equals(2000)))
        .get();
    expect(pages.length, 3);
    expect(pages.map((p) => p.relativePath),
        ['552/2000/000.jpg', '552/2000/001.jpg', '552/2000/002.jpg']);

    final c = (await db.chaptersForManga(552)).single;
    expect(c.deviceState, OfflineDeviceState.downloaded);
    expect(c.bytes, 9); // 3 pages * 3 bytes
  });

  test('downloadChapter refuses a chapter not downloaded server-side',
      () async {
    final chapter = await seedChapter(serverDownloaded: false);
    expect(() => managerWith().downloadChapter(chapter), throwsStateError);
    final c = (await db.chaptersForManga(552)).single;
    expect(c.deviceState, OfflineDeviceState.none);
  });

  test('a failure mid-download cleans up and marks error', () async {
    final chapter = await seedChapter();
    var calls = 0;
    final mgr = managerWith(bytes: (url) async {
      if (calls++ == 1) throw Exception('network blip');
      return (bytes: [1, 2, 3], ext: 'jpg');
    });

    await expectLater(mgr.downloadChapter(chapter), throwsException);

    final c = (await db.chaptersForManga(552)).single;
    expect(c.deviceState, OfflineDeviceState.error);
    final pages = await (db.select(db.offlinePages)
          ..where((t) => t.chapterId.equals(2000)))
        .get();
    expect(pages, isEmpty, reason: 'partial page rows purged');
    expect(store.deletedChapters, contains(2000),
        reason: 'partial files purged');
  });

  test('deleteChapter removes files, page rows, and resets state', () async {
    final chapter = await seedChapter();
    await managerWith().downloadChapter(chapter);
    final downloaded = (await db.chaptersForManga(552)).single;

    await managerWith().deleteChapter(downloaded);

    final c = (await db.chaptersForManga(552)).single;
    expect(c.deviceState, OfflineDeviceState.none);
    expect(c.bytes, 0);
    final pages = await (db.select(db.offlinePages)
          ..where((t) => t.chapterId.equals(2000)))
        .get();
    expect(pages, isEmpty);
  });

  // Mirrors the coordinator's onPageStored guard: check device state and insert
  // the page row in one transaction, so it serializes with deleteChapter.
  Future<void> storePageIfLive(int chapterId, int pageIndex, String rel) =>
      db.transaction(() async {
        final c = await db.chapterById(chapterId);
        if (c == null || c.deviceState == OfflineDeviceState.none) return;
        await db.into(db.offlinePages).insertOnConflictUpdate(
              OfflinePagesCompanion.insert(
                  chapterId: chapterId,
                  pageIndex: pageIndex,
                  relativePath: rel),
            );
      });

  test('a page stored after deleteChapter is rejected (state is none)',
      () async {
    final chapter = await seedChapter();
    await managerWith().downloadChapter(chapter);

    await managerWith().deleteChapter((await db.chaptersForManga(552)).single);
    // A page callback that fired just before the delete finally lands.
    await storePageIfLive(2000, 5, '552/2000/005.jpg');

    final rows = await (db.select(db.offlinePages)
          ..where((t) => t.chapterId.equals(2000)))
        .get();
    expect(rows, isEmpty,
        reason: 'the insert reads state=none and skips — no resurrected row');
  });

  test('a page store racing deleteChapter leaves no orphan row', () async {
    final chapter = await seedChapter();
    await db.setChapterDeviceState(chapter.id, OfflineDeviceState.downloading);
    final downloading = (await db.chaptersForManga(552)).single;

    await Future.wait([
      managerWith().deleteChapter(downloading),
      storePageIfLive(2000, 5, '552/2000/005.jpg'),
    ]);

    expect((await db.chaptersForManga(552)).single.deviceState,
        OfflineDeviceState.none);
    final rows = await (db.select(db.offlinePages)
          ..where((t) => t.chapterId.equals(2000)))
        .get();
    expect(rows, isEmpty,
        reason: 'state=none + row purge is one transaction — nothing survives');
  });

  test('sweepInterrupted resets chapters stuck downloading', () async {
    final chapter = await seedChapter();
    await db.setChapterDeviceState(chapter.id, OfflineDeviceState.downloading);

    await managerWith().sweepInterrupted();

    final c = (await db.chaptersForManga(552)).single;
    expect(c.deviceState, OfflineDeviceState.none);
  });
}
