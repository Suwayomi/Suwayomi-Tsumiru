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
      id: 5,
      mangaId: 1,
      name: 'c',
      chapterIndex: 0,
      isRead: false,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: true,
      pageCount: 2,
      updatedAt: DateTime(2026),
    );
    await db.setChapterDeviceState(5, OfflineDeviceState.downloading);
  });
  tearDown(() async {
    await db.close();
    // A _quietDeleteDir retry (50 ms backoff) may leave a .superseded dir
    // briefly locked by the Windows file indexer. If tmp.delete then throws,
    // the framework marks the test itself failed — so silence the error here;
    // the test's own assertions already validated the correct outcome.
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> replay() => replayCompletionLog(
    db: db,
    store: store,
    log: log,
    catalogServerId: 'srv',
  );

  /// Stage [pages] of chapter [c], as an interrupted or finished worker would.
  Future<void> stage(
    int m,
    int c,
    List<int> indices,
    List<int> pages, {
    int generation = 0,
  }) async {
    await store.beginChapter(
      m,
      c,
      ChapterManifest(generation: generation, indices: indices),
    );
    for (final i in pages) {
      await store.writePage(m, c, i, List.filled(10, 0), 'jpg');
    }
  }

  bool finalDirExists(int m, int c) =>
      Directory(paths.absolute(paths.chapterDirRel(m, c))).existsSync();
  bool stagingExists(int m, int c) =>
      Directory(paths.absolute(paths.chapterStagingDirRel(m, c))).existsSync();

  test(
    'a kill between the commit rename and its catalog write is adopted',
    () async {
      // Exactly the crash the design leaves open: the directory is in place and
      // complete, but the transaction that would have recorded it never ran.
      await stage(1, 5, [0, 1], [0, 1]);
      expect(await store.commitStaging(1, 5), isNotNull);
      // No commitDownloadedChapter — that is the write we are pretending was lost.
      expect(await db.downloadedPageCount(5), 0);

      await replay();

      expect(
        (await db.chapterById(5))!.deviceState,
        OfflineDeviceState.downloaded,
      );
      expect(await db.downloadedPageCount(5), 2);
    },
  );

  test(
    'a deleted chapter is not resurrected and its files are swept',
    () async {
      await stage(1, 5, [0, 1], [0, 1]);
      await db.setChapterDeviceState(5, OfflineDeviceState.none);

      await replay();

      expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.none);
      expect(await db.downloadedPageCount(5), 0);
      expect(stagingExists(1, 5), isFalse);
      expect(finalDirExists(1, 5), isFalse);
    },
  );
}
