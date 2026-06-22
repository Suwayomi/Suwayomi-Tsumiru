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
