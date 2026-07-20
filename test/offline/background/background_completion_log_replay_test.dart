// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/background/background_completion_log.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';

import '../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  late Directory tmp;
  late OfflinePaths paths;
  late BackgroundCompletionLog log;

  setUp(() async {
    db = testOfflineDatabase();
    tmp = await Directory.systemTemp.createTemp('replay');
    paths = OfflinePaths(tmp.path);
    log = BackgroundCompletionLog(File('${tmp.path}/.bg_completion.log'));
    // a manga + a downloading chapter exist in drift:
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

  Future<void> writePageFile(int m, int c, int i) async {
    final f = File(paths.absolute(paths.pageRel(m, c, i, 'jpg')));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(List.filled(10, 0));
  }

  test('a page on disk with NO log line still gets a drift row (filesystem truth)',
      () async {
    await writePageFile(1, 5, 0);
    await writePageFile(1, 5, 1);
    // log only recorded page 0 + a downloaded terminal (page 1 line was lost):
    await log.appendPage(chapterId: 5, mangaId: 1, pageIndex: 0, relPath: paths.pageRel(1, 5, 0, 'jpg'), bytes: 10);
    await log.appendChapter(chapterId: 5, status: 'downloaded', pages: 2, bytes: 20);

    await replayCompletionLog(
        db: db, paths: paths, log: log,
        measureBytes: (m, c) async => 20);

    expect(await db.downloadedPageCount(5), 2); // both pages, from the filesystem
    final ch = await db.chapterById(5);
    expect(ch!.deviceState, OfflineDeviceState.downloaded);
    expect(await log.parse(), isEmpty); // truncated
  });

  test('a deleted chapter (drift row gone) is NOT resurrected', () async {
    await writePageFile(1, 5, 0);
    await log.appendPage(chapterId: 5, mangaId: 1, pageIndex: 0, relPath: paths.pageRel(1, 5, 0, 'jpg'), bytes: 10);
    // user deleted it: state -> none
    await db.setChapterDeviceState(5, OfflineDeviceState.none);

    await replayCompletionLog(
        db: db, paths: paths, log: log, measureBytes: (m, c) async => 10);

    expect(await db.downloadedPageCount(5), 0); // no rows added
    final ch = await db.chapterById(5);
    expect(ch!.deviceState, OfflineDeviceState.none);
  });

  test('a delete committing mid-replay wins (recheck inside the transaction)',
      () async {
    await writePageFile(1, 5, 0);
    await log.appendPage(
        chapterId: 5,
        mangaId: 1,
        pageIndex: 0,
        relPath: paths.pageRel(1, 5, 0, 'jpg'),
        bytes: 10);
    await log.appendChapter(chapterId: 5, status: 'downloaded', pages: 1, bytes: 10);

    // measureBytes fires after replay's initial state check but before its write
    // transaction — the seam where a concurrent delete commits.
    await replayCompletionLog(
        db: db,
        paths: paths,
        log: log,
        measureBytes: (m, c) async {
          await db.setChapterDeviceState(5, OfflineDeviceState.none);
          return 10;
        });

    expect(await db.downloadedPageCount(5), 0, reason: 'no rows resurrected');
    expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.none,
        reason: 'the delete wins over the replay');
  });

  test('a delete tombstone stops a stale entry completing a re-queued chapter',
      () async {
    // Generation 1: the chapter finished (log has downloaded), not yet replayed.
    await writePageFile(1, 5, 0);
    await log.appendPage(
        chapterId: 5,
        mangaId: 1,
        pageIndex: 0,
        relPath: paths.pageRel(1, 5, 0, 'jpg'),
        bytes: 10);
    await log.appendChapter(chapterId: 5, status: 'downloaded', pages: 1, bytes: 10);
    // The user deletes it (tombstone bumps to generation 1), its files go, then
    // re-queues it.
    await log.appendDeleted(5, 1);
    await File(paths.absolute(paths.pageRel(1, 5, 0, 'jpg'))).delete();
    await db.setChapterDeviceState(5, OfflineDeviceState.none);
    await db.setChapterDeviceState(5, OfflineDeviceState.queued);

    await replayCompletionLog(
        db: db, paths: paths, log: log, measureBytes: (m, c) async => 10);

    final ch = await db.chapterById(5);
    expect(ch!.deviceState, OfflineDeviceState.queued,
        reason: 'the stale downloaded entry must not complete the new generation');
    expect(await db.downloadedPageCount(5), 0, reason: 'no stale rows applied');
  });

  test('a late downloaded entry after the tombstone cannot complete with no files',
      () async {
    // The worker was paused between its final page write and its terminal append,
    // so the log order is pages -> tombstone -> stale downloaded. The files were
    // deleted, so the filesystem check must reject the stale completion.
    await log.appendPage(
        chapterId: 5,
        mangaId: 1,
        pageIndex: 0,
        relPath: paths.pageRel(1, 5, 0, 'jpg'),
        bytes: 10);
    await log.appendDeleted(5, 1);
    // A current-generation downloaded whose files aren't actually on disk (a
    // torn/partial download) — the filesystem check must still reject it.
    await log.appendChapter(
        chapterId: 5, status: 'downloaded', pages: 1, bytes: 10, generation: 1);
    // Files gone (deleted), chapter re-queued.
    await db.setChapterDeviceState(5, OfflineDeviceState.none);
    await db.setChapterDeviceState(5, OfflineDeviceState.queued);

    await replayCompletionLog(
        db: db, paths: paths, log: log, measureBytes: (m, c) async => 10);

    expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.queued,
        reason: 'no files on disk — a stale downloaded must not complete it');
    expect(await db.downloadedPageCount(5), 0);
  });

  test('a .part staging file does not count as a completed page', () async {
    // Only an in-flight atomic-write staging file exists; a stale downloaded
    // entry must not complete the chapter off it.
    final part = File('${paths.absolute(paths.pageRel(1, 5, 0, 'jpg'))}.part');
    await part.parent.create(recursive: true);
    await part.writeAsBytes(List.filled(10, 0));
    await log.appendChapter(chapterId: 5, status: 'downloaded', pages: 1, bytes: 10);

    await replayCompletionLog(
        db: db, paths: paths, log: log, measureBytes: (m, c) async => 10);

    expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.downloading,
        reason: 'a .part file is not a completed page');
    expect(await db.downloadedPageCount(5), 0);
  });

  test('a re-download after a tombstone still completes normally', () async {
    await log.appendChapter(chapterId: 5, status: 'downloaded', pages: 1, bytes: 10);
    await log.appendDeleted(5, 1);
    // Generation 1: re-downloaded after the delete, tagged with the new gen.
    await writePageFile(1, 5, 0);
    await db.setChapterDeviceState(5, OfflineDeviceState.downloading);
    await log.appendChapter(
        chapterId: 5, status: 'downloaded', pages: 1, bytes: 10, generation: 1);

    await replayCompletionLog(
        db: db, paths: paths, log: log, measureBytes: (m, c) async => 10);

    expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.downloaded,
        reason: 'entries logged after the tombstone still apply');
    expect(await db.downloadedPageCount(5), 1);
  });

  test('a stale error appended after the tombstone is dropped on replay',
      () async {
    // The exact durable ordering: generation-0 activity, tombstone(gen 1), then
    // the worker's late generation-0 error, then generation-1 activity.
    await db.setChapterDeviceState(5, OfflineDeviceState.downloading);
    await log.appendDeleted(5, 1);
    await log.appendChapter(
        chapterId: 5, status: 'error', pages: 0, bytes: 0, generation: 0);
    // Generation 1 re-download completes with its page on disk.
    await writePageFile(1, 5, 0);
    await log.appendChapter(
        chapterId: 5, status: 'downloaded', pages: 1, bytes: 10, generation: 1);

    await replayCompletionLog(
        db: db, paths: paths, log: log, measureBytes: (m, c) async => 10);

    expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.downloaded,
        reason: 'the stale generation-0 error must not override the new download');
  });

  group('applyBackgroundTerminalState (live worker events)', () {
    test('a stale downloaded event cannot complete a re-queued chapter with too '
        'few pages', () async {
      // Chapter 5 exists with pageCount 2 but no page rows (deleted + re-queued).
      await db.setChapterDeviceState(5, OfflineDeviceState.queued);
      await applyBackgroundTerminalState(
          db: db, chapterId: 5, status: 'downloaded', bytes: 10);
      expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.queued,
          reason: 'no pages present — a stale downloaded must not complete it');
    });

    test('a downloaded event completes when all pages are present', () async {
      await db.setChapterDeviceState(5, OfflineDeviceState.downloading);
      await db.into(db.offlinePages).insert(OfflinePagesCompanion.insert(
          chapterId: 5, pageIndex: 0, relativePath: '1/5/0.jpg'));
      await db.into(db.offlinePages).insert(OfflinePagesCompanion.insert(
          chapterId: 5, pageIndex: 1, relativePath: '1/5/1.jpg'));
      await applyBackgroundTerminalState(
          db: db, chapterId: 5, status: 'downloaded', bytes: 20);
      expect((await db.chapterById(5))!.deviceState,
          OfflineDeviceState.downloaded);
    });

    test('a stale error event does not error a freshly queued chapter', () async {
      await db.setChapterDeviceState(5, OfflineDeviceState.queued);
      await applyBackgroundTerminalState(
          db: db, chapterId: 5, status: 'error', bytes: 0);
      expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.queued,
          reason: 'error applies only to a chapter actually mid-download');
    });

    test('an error event fails a chapter that is downloading', () async {
      await db.setChapterDeviceState(5, OfflineDeviceState.downloading);
      await applyBackgroundTerminalState(
          db: db, chapterId: 5, status: 'error', bytes: 0);
      expect(
          (await db.chapterById(5))!.deviceState, OfflineDeviceState.error);
    });

    test('a downloaded event never resurrects a deleted chapter', () async {
      await db.setChapterDeviceState(5, OfflineDeviceState.none);
      await applyBackgroundTerminalState(
          db: db, chapterId: 5, status: 'downloaded', bytes: 10);
      expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.none);
    });

    test('a stale-generation error is dropped even for a downloading chapter',
        () async {
      // Generation 0's error arrives after a delete bumped drift to generation 1
      // and a new download reached downloading.
      await db.setChapterDeviceState(5, OfflineDeviceState.downloading);
      await db.bumpChapterGeneration(5); // now generation 1
      await applyBackgroundTerminalState(
          db: db, chapterId: 5, status: 'error', bytes: 0, eventGeneration: 0);
      expect((await db.chapterById(5))!.deviceState,
          OfflineDeviceState.downloading,
          reason: 'a deleted generation event must not touch the new one');
    });

    test('a current-generation error still applies', () async {
      await db.setChapterDeviceState(5, OfflineDeviceState.downloading);
      await db.bumpChapterGeneration(5); // now generation 1
      await applyBackgroundTerminalState(
          db: db, chapterId: 5, status: 'error', bytes: 0, eventGeneration: 1);
      expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.error);
    });

    test('the persisted generation increments monotonically (no restart reuse)',
        () async {
      // The generation lives in drift, so a restart (which would reset an
      // in-memory counter) can't make a second delete reuse a generation.
      expect(await db.bumpChapterGeneration(5), 1); // first delete
      expect(await db.bumpChapterGeneration(5), 2); // second delete, not reused
      // A late generation-1 event is now stale against the persisted 2.
      await db.setChapterDeviceState(5, OfflineDeviceState.downloading);
      await applyBackgroundTerminalState(
          db: db, chapterId: 5, status: 'error', bytes: 0, eventGeneration: 1);
      expect((await db.chapterById(5))!.deviceState,
          OfflineDeviceState.downloading,
          reason: 'a superseded generation event stays stale after a restart');
    });
  });

  test('double-replay is idempotent', () async {
    await writePageFile(1, 5, 0);
    await writePageFile(1, 5, 1);
    await log.appendChapter(chapterId: 5, status: 'downloaded', pages: 2, bytes: 20);
    await replayCompletionLog(db: db, paths: paths, log: log, measureBytes: (m, c) async => 20);
    // replay again on the (now empty) log — must not throw or change counts
    await replayCompletionLog(db: db, paths: paths, log: log, measureBytes: (m, c) async => 20);
    expect(await db.downloadedPageCount(5), 2);
  });
}
