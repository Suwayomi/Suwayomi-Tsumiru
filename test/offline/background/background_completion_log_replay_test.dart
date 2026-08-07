// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/background/background_completion_log.dart';
import 'package:tsumiru/src/features/offline/data/chapter_commit.dart';
import 'package:tsumiru/src/features/offline/data/chapter_manifest.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';

import '../../helpers/offline_test_db.dart';

/// Recovery runs against the real page store on a real temp directory: the
/// whole point of the design is what the filesystem looks like after a kill, so
/// a mocked store would test the mock.
void main() {
  late OfflineDatabase db;
  late Directory tmp;
  late OfflinePaths paths;
  late IoOfflinePageStore store;
  late BackgroundCompletionLog log;

  setUp(() async {
    ChapterFileLock.resetForTest();
    db = testOfflineDatabase();
    tmp = await Directory.systemTemp.createTemp('replay');
    paths = OfflinePaths(tmp.path);
    store = IoOfflinePageStore(paths);
    log = BackgroundCompletionLog(File('${tmp.path}/.bg_completion.log'));
    await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
    await db.upsertChapterMetadata(
        id: 5, mangaId: 1, name: 'c', chapterIndex: 0, isRead: false,
        lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
        pageCount: 2, updatedAt: DateTime(2026));
    await db.setChapterDeviceState(5, OfflineDeviceState.downloading);
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<void> replay() => replayCompletionLog(
      db: db, paths: paths, store: store, log: log, catalogServerId: 'srv');

  /// Stage [pages] of chapter [c], as an interrupted or finished worker would.
  Future<void> stage(int m, int c, List<int> indices, List<int> pages,
      {int generation = 0}) async {
    await store.beginChapter(
        m, c, ChapterManifest(generation: generation, indices: indices));
    for (final i in pages) {
      await store.writePage(m, c, i, List.filled(10, 0), 'jpg');
    }
  }

  bool finalDirExists(int m, int c) =>
      Directory(paths.absolute(paths.chapterDirRel(m, c))).existsSync();
  bool stagingExists(int m, int c) =>
      Directory(paths.absolute(paths.chapterStagingDirRel(m, c))).existsSync();

  test('complete staging is committed even with no terminal line in the log',
      () async {
    // The worker was killed after its last page but before it could record
    // anything. Recovery reads the directory, not the log.
    await stage(1, 5, [0, 1], [0, 1]);

    await replay();

    expect((await db.chapterById(5))!.deviceState,
        OfflineDeviceState.downloaded);
    expect(await db.downloadedPageCount(5), 2);
    expect(finalDirExists(1, 5), isTrue);
    expect(stagingExists(1, 5), isFalse);
    expect(await log.parse(), isEmpty); // truncated
  });

  test('a chapter killed mid-download is left absent, never blank', () async {
    // One of two pages made it. The chapter must not appear at all.
    await stage(1, 5, [0, 1], [0]);

    await replay();

    expect((await db.chapterById(5))!.deviceState,
        OfflineDeviceState.downloading,
        reason: 'still resumable');
    expect(await db.downloadedPageCount(5), 0, reason: 'nothing published');
    expect(finalDirExists(1, 5), isFalse, reason: 'no half-chapter on disk');
    expect(stagingExists(1, 5), isTrue, reason: 'staging kept for the resume');
  });

  test('a kill between the commit rename and its catalog write is adopted',
      () async {
    // Exactly the crash the design leaves open: the directory is in place and
    // complete, but the transaction that would have recorded it never ran.
    await stage(1, 5, [0, 1], [0, 1]);
    expect(await store.commitStaging(1, 5), isNotNull);
    // No commitDownloadedChapter — that is the write we are pretending was lost.
    expect(await db.downloadedPageCount(5), 0);

    await replay();

    expect((await db.chapterById(5))!.deviceState,
        OfflineDeviceState.downloaded);
    expect(await db.downloadedPageCount(5), 2);
  });

  test('a deleted chapter is not resurrected and its files are swept', () async {
    await stage(1, 5, [0, 1], [0, 1]);
    await db.setChapterDeviceState(5, OfflineDeviceState.none);

    await replay();

    expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.none);
    expect(await db.downloadedPageCount(5), 0);
    expect(stagingExists(1, 5), isFalse);
    expect(finalDirExists(1, 5), isFalse);
  });

  test('a complete final dir under a deleted row is deleted, honouring the user',
      () async {
    // Crash mid-delete: the row was cleared but the files outlived it.
    await stage(1, 5, [0, 1], [0, 1]);
    await store.commitStaging(1, 5);
    await db.setChapterDeviceState(5, OfflineDeviceState.none);

    await replay();

    expect(finalDirExists(1, 5), isFalse);
    expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.none);
  });

  test('staging from a superseded generation cannot commit', () async {
    // The worker finished at generation 0; a delete then bumped drift to 1 and
    // the chapter was re-queued. Those pages belong to nobody now.
    await stage(1, 5, [0, 1], [0, 1]);
    await db.bumpChapterGeneration(5);
    await db.setChapterDeviceState(5, OfflineDeviceState.queued);

    await replay();

    expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.queued,
        reason: 'the stale download must not complete the new generation');
    expect(await db.downloadedPageCount(5), 0);
    expect(stagingExists(1, 5), isFalse, reason: 'refused staging is dropped');
  });

  test('a re-download at the current generation still commits', () async {
    await db.bumpChapterGeneration(5); // now generation 1
    await stage(1, 5, [0, 1], [0, 1], generation: 1);
    await log.appendDeleted(5, 1);

    await replay();

    expect((await db.chapterById(5))!.deviceState,
        OfflineDeviceState.downloaded);
    expect(await db.downloadedPageCount(5), 2);
  });

  test('a half-written .tmp page does not count toward completeness', () async {
    await store.beginChapter(
        1, 5, const ChapterManifest(generation: 0, indices: [0, 1]));
    await store.writePage(1, 5, 0, List.filled(10, 0), 'jpg');
    // Page 1 was killed mid-write, leaving the temp name behind.
    final partial = File(
        '${paths.absolute(paths.stagingPageRel(1, 5, 1, 'jpg'))}.tmp');
    await partial.writeAsBytes(List.filled(10, 0));

    await replay();

    expect((await db.chapterById(5))!.deviceState,
        OfflineDeviceState.downloading);
    expect(finalDirExists(1, 5), isFalse);
    expect(await partial.exists(), isFalse, reason: 'swept on the resume scan');
  });

  test('a legacy downloaded chapter is grandfathered, not re-fetched', () async {
    // A directory written before chapters were atomic: pages, no manifest.
    final dir = Directory(paths.absolute(paths.chapterDirRel(1, 5)));
    await dir.create(recursive: true);
    await File('${dir.path}/000.jpg').writeAsBytes(List.filled(10, 0));
    await db.setChapterDeviceState(5, OfflineDeviceState.downloaded);

    await replay();

    expect((await db.chapterById(5))!.deviceState,
        OfflineDeviceState.downloaded,
        reason: 'nothing can prove it whole, and re-fetching every library is '
            'not a trade worth making');
    expect(finalDirExists(1, 5), isTrue);
  });

  test('a legacy chapter left mid-download is cleared for one re-fetch',
      () async {
    final dir = Directory(paths.absolute(paths.chapterDirRel(1, 5)));
    await dir.create(recursive: true);
    await File('${dir.path}/000.jpg').writeAsBytes(List.filled(10, 0));
    await db.setChapterDeviceState(5, OfflineDeviceState.downloading);

    await replay();

    expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.queued);
    expect(finalDirExists(1, 5), isFalse);
    expect(await db.downloadedPageCount(5), 0);
  });

  test('catch-up files with no row are adopted and committed', () async {
    await db.setKeepRule(1, OfflineKeepRule.all, 3);
    await stage(1, 9, [0, 1], [0, 1]);
    await log.appendAdopt(const AdoptChapterEntry(
      chapterId: 9,
      mangaId: 1,
      serverId: 'srv',
      name: 'caught up',
      chapterIndex: 2,
      chapterNumber: 3,
      pageCount: 2,
      bytes: 20,
      isRead: false,
    ));

    await replay();

    final adopted = await db.chapterById(9);
    expect(adopted!.deviceState, OfflineDeviceState.downloaded);
    expect(await db.downloadedPageCount(9), 2);
  });

  test('a catch-up record from another server is refused and swept', () async {
    await db.setKeepRule(1, OfflineKeepRule.all, 3);
    await stage(1, 9, [0, 1], [0, 1]);
    await log.appendAdopt(const AdoptChapterEntry(
      chapterId: 9,
      mangaId: 1,
      serverId: 'a-different-server',
      name: 'caught up',
      chapterIndex: 2,
      chapterNumber: 3,
      pageCount: 2,
      bytes: 20,
      isRead: false,
    ));

    await replay();

    expect(await db.chapterById(9), isNull);
    expect(stagingExists(1, 9), isFalse);
    expect(finalDirExists(1, 9), isFalse);
  });

  test('double-replay is idempotent', () async {
    await stage(1, 5, [0, 1], [0, 1]);
    await replay();
    await replay();
    expect(await db.downloadedPageCount(5), 2);
    expect((await db.chapterById(5))!.deviceState,
        OfflineDeviceState.downloaded);
  });

  group('applyBackgroundTerminalState (live worker events)', () {
    test('an error event fails a chapter that is downloading', () async {
      await db.setChapterDeviceState(5, OfflineDeviceState.downloading);
      await applyBackgroundTerminalState(
          db: db, chapterId: 5, status: 'error');
      expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.error);
    });

    test('a stale error event does not error a freshly queued chapter',
        () async {
      await db.setChapterDeviceState(5, OfflineDeviceState.queued);
      await applyBackgroundTerminalState(
          db: db, chapterId: 5, status: 'error');
      expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.queued,
          reason: 'error applies only to a chapter actually mid-download');
    });

    test('a success never arrives this way — only a commit publishes', () async {
      await db.setChapterDeviceState(5, OfflineDeviceState.downloading);
      await applyBackgroundTerminalState(
          db: db, chapterId: 5, status: 'downloaded');
      expect((await db.chapterById(5))!.deviceState,
          OfflineDeviceState.downloading,
          reason: 'a log line claiming success cannot publish a chapter');
    });

    test('an event never resurrects a deleted chapter', () async {
      await db.setChapterDeviceState(5, OfflineDeviceState.none);
      await applyBackgroundTerminalState(
          db: db, chapterId: 5, status: 'error');
      expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.none);
    });

    test('a stale-generation error is dropped even for a downloading chapter',
        () async {
      await db.setChapterDeviceState(5, OfflineDeviceState.downloading);
      await db.bumpChapterGeneration(5); // now generation 1
      await applyBackgroundTerminalState(
          db: db, chapterId: 5, status: 'error', eventGeneration: 0);
      expect((await db.chapterById(5))!.deviceState,
          OfflineDeviceState.downloading,
          reason: 'a deleted generation event must not touch the new one');
    });

    test('a current-generation error still applies', () async {
      await db.setChapterDeviceState(5, OfflineDeviceState.downloading);
      await db.bumpChapterGeneration(5); // now generation 1
      await applyBackgroundTerminalState(
          db: db, chapterId: 5, status: 'error', eventGeneration: 1);
      expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.error);
    });

    test('the persisted generation increments monotonically (no restart reuse)',
        () async {
      // The generation lives in drift, so a restart (which would reset an
      // in-memory counter) can't make a second delete reuse a generation.
      expect(await db.bumpChapterGeneration(5), 1); // first delete
      expect(await db.bumpChapterGeneration(5), 2); // second delete, not reused
      await db.setChapterDeviceState(5, OfflineDeviceState.downloading);
      await applyBackgroundTerminalState(
          db: db, chapterId: 5, status: 'error', eventGeneration: 1);
      expect((await db.chapterById(5))!.deviceState,
          OfflineDeviceState.downloading,
          reason: 'a superseded generation event stays stale after a restart');
    });
  });
}
