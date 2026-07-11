// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_coordinator.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store.dart';

import '../../../../helpers/offline_test_db.dart';

/// In-memory page store — "writes" pages to a map keyed by chapter/page.
class _FakeStore implements OfflinePageStore {
  final pages = <String, int>{}; // '$chapter/$page' -> bytes
  @override
  Future<({String relPath, int bytes})> writePage(int mangaId, int chapterId,
      int pageIndex, List<int> bytes, String ext) async {
    pages['$chapterId/$pageIndex'] = bytes.length;
    return (
      relPath: '$mangaId/$chapterId/$pageIndex.$ext',
      bytes: bytes.length
    );
  }

  @override
  Future<void> deleteChapter(int mangaId, int chapterId) async {}
  @override
  Future<int> chapterBytes(int mangaId, int chapterId) async {
    var total = 0;
    for (final e in pages.entries) {
      if (e.key.startsWith('$chapterId/')) total += e.value;
    }
    return total;
  }

  @override
  Future<void> clearAll() async {}
}

void main() {
  late OfflineDatabase db;
  late _FakeStore store;
  setUp(() {
    db = testOfflineDatabase();
    store = _FakeStore();
  });
  tearDown(() => db.close());

  Future<void> seedChapter(int id, int mangaId, int pageCount) =>
      db.upsertChapterMetadata(
          id: id,
          mangaId: mangaId,
          name: 'c$id',
          chapterIndex: 1,
          isRead: false,
          lastPageRead: 0,
          isBookmarked: false,
          serverIsDownloaded: true,
          pageCount: pageCount,
          updatedAt: DateTime(2026));

  /// Build a coordinator whose engine fetches with the given behaviour.
  OfflineDownloadCoordinator coord({
    List<String> pages = const ['/p/0', '/p/1', '/p/2'],
    bool fail = false,
    bool auth401 = false,
    bool refreshOk = false,
    bool Function()? persistedPaused,
  }) {
    final engine = ChapterDownloadEngine(
      writePage: store,
      maxAttempts: 2,
      backoff: (_) => Duration.zero,
      refreshAuth: () async => refreshOk,
      fetchPage: (url) async {
        if (auth401) throw const PageAuthException();
        if (fail) throw Exception('boom');
        return (bytes: [1, 2, 3], ext: 'jpg');
      },
    );
    return OfflineDownloadCoordinator(
      db: db,
      engine: engine,
      resolvePages: (_) async => pages,
      measureChapterBytes: store.chapterBytes,
      persistedPaused: persistedPaused,
    );
  }

  test('downloads every page, stores rows, marks downloaded with bytes',
      () async {
    await seedChapter(1, 7, 3);
    await coord().enqueueChapter((await db.chapterById(1))!);
    final c = await db.chapterById(1);
    expect(c!.deviceState, OfflineDeviceState.downloaded);
    expect(await db.downloadedPageCount(1), 3);
    expect(c.bytes, 9); // 3 pages x 3 bytes
  });

  test('no resolved pages -> error', () async {
    await seedChapter(1, 7, 3);
    await coord(pages: const []).enqueueChapter((await db.chapterById(1))!);
    expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.error);
  });

  test('resume only fetches pages not already on disk', () async {
    await seedChapter(1, 7, 3);
    await db.into(db.offlinePages).insert(OfflinePagesCompanion.insert(
        chapterId: 1, pageIndex: 0, relativePath: '7/1/0.jpg'));
    await coord().enqueueChapter((await db.chapterById(1))!);
    expect(
        (await db.chapterById(1))!.deviceState, OfflineDeviceState.downloaded);
    expect(store.pages.keys.toSet(), {'1/1', '1/2'}); // only the 2 missing
  });

  test('auth failure (401 + refresh dead) -> error', () async {
    await seedChapter(1, 7, 3);
    await coord(auth401: true, refreshOk: false)
        .enqueueChapter((await db.chapterById(1))!);
    expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.error);
  });

  test('transient fetch failure exhausts retries -> error', () async {
    await seedChapter(1, 7, 3);
    await coord(fail: true).enqueueChapter((await db.chapterById(1))!);
    expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.error);
  });

  test('queueChapter marks queued without downloading', () async {
    await seedChapter(1, 7, 3);
    await coord().queueChapter(1);
    expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.queued);
    expect(store.pages, isEmpty);
  });

  test('pump drains the queue one chapter at a time', () async {
    await seedChapter(1, 7, 2);
    await seedChapter(2, 7, 2);
    final c = coord(pages: const ['/p/0', '/p/1']);
    await c.queueChapter(1);
    await c.queueChapter(2);
    await c.pumpDownloads();
    expect(
        (await db.chapterById(1))!.deviceState, OfflineDeviceState.downloaded);
    expect(
        (await db.chapterById(2))!.deviceState, OfflineDeviceState.downloaded);
  });

  test('pump resumes a chapter stranded as downloading', () async {
    await seedChapter(1, 7, 2);
    await db.setChapterDeviceState(1, OfflineDeviceState.downloading);
    await coord(pages: const ['/p/0', '/p/1']).pumpDownloads();
    expect(
        (await db.chapterById(1))!.deviceState, OfflineDeviceState.downloaded);
  });

  test('paused pump does not download queued chapters', () async {
    await seedChapter(1, 7, 2);
    final c = coord(pages: const ['/p/0', '/p/1']);
    await c.queueChapter(1);
    c.pause();
    await c.pumpDownloads();
    expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.queued);
    expect(store.pages, isEmpty);
  });

  test('paused enqueueChapter is a no-op (no re-start of a stranded chapter)',
      () async {
    await seedChapter(1, 7, 2);
    await db.setChapterDeviceState(1, OfflineDeviceState.downloading);
    final c = coord(pages: const ['/p/0', '/p/1']);
    c.pause();
    await c.enqueueChapter((await db.chapterById(1))!);
    // Left as-is (resumable), nothing written.
    expect(
        (await db.chapterById(1))!.deviceState, OfflineDeviceState.downloading);
    expect(store.pages, isEmpty);
  });

  test('resume after pause drains the queue', () async {
    await seedChapter(1, 7, 2);
    final c = coord(pages: const ['/p/0', '/p/1']);
    await c.queueChapter(1);
    c.pause();
    await c.pumpDownloads(); // gated — no-op
    expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.queued);
    await c.resume();
    expect(
        (await db.chapterById(1))!.deviceState, OfflineDeviceState.downloaded);
  });

  test('persisted pause flag gates the pump even on a fresh coordinator',
      () async {
    await seedChapter(1, 7, 2);
    var paused = true; // simulates the saved flag after a restart
    final c =
        coord(pages: const ['/p/0', '/p/1'], persistedPaused: () => paused);
    await c.queueChapter(1);
    await c.pumpDownloads();
    expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.queued);
    paused = false; // user resumes
    await c.pumpDownloads();
    expect(
        (await db.chapterById(1))!.deviceState, OfflineDeviceState.downloaded);
  });
}
