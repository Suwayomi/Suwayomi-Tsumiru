// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../utils/logger/logger.dart';
import 'chapter_commit.dart';
import 'chapter_manifest.dart';
import 'offline_database.dart';
import 'offline_page_store.dart';

typedef PageUrlsFetcher = Future<List<String>> Function(int chapterId);

typedef PageBytesFetcher = Future<PageBytes> Function(String url);

class OfflineDownloadManager {
  OfflineDownloadManager({
    required this.db,
    required this.store,
    required this.fetchPageUrls,
    required this.fetchBytes,
  });

  final OfflineDatabase db;
  final OfflinePageStore store;
  final PageUrlsFetcher fetchPageUrls;
  final PageBytesFetcher fetchBytes;

  /// Requires a server-downloaded chapter; failures purge partial staging, mark error, and rethrow.
  Future<void> downloadChapter(
    OfflineChapter chapter, {
    bool force = false,
  }) async {
    if (!force && !chapter.serverIsDownloaded) {
      throw StateError(
        'Chapter ${chapter.id} is not downloaded server-side (server-first)',
      );
    }
    await db.setChapterDeviceState(chapter.id, OfflineDeviceState.downloading);
    var pageCount = 0;
    var atPage = -1;
    try {
      final urls = await fetchPageUrls(chapter.id);
      pageCount = urls.length;
      logger.i(
        'Offline: downloading chapter ${chapter.id} '
        '(manga ${chapter.mangaId}, $pageCount pages)',
      );
      final generation =
          (await db.chapterById(chapter.id))?.downloadGeneration ?? 0;
      // beginChapter replaces only the manifest; clear old pages before starting a fresh download.
      await store.deleteStaging(chapter.mangaId, chapter.id);
      await store.beginChapter(
        chapter.mangaId,
        chapter.id,
        ChapterManifest(
          generation: generation,
          indices: [for (var i = 0; i < urls.length; i++) i],
        ),
      );
      for (var i = 0; i < urls.length; i++) {
        atPage = i;
        final page = await fetchBytes(urls[i]);
        await store.writePage(
          chapter.mangaId,
          chapter.id,
          i,
          page.bytes,
          page.ext,
        );
      }
      final result = await commitStagedChapter(
        db: db,
        store: store,
        mangaId: chapter.mangaId,
        chapterId: chapter.id,
      );
      // Empty staging must fail rather than leave a downloading row selected on every reconcile.
      if (result == ChapterCommitResult.incomplete) {
        throw StateError(
          'Chapter ${chapter.id} produced no pages to commit '
          '(pageCount=$pageCount)',
        );
      }
    } catch (e, st) {
      logger.e(
        'Offline: download FAILED for chapter ${chapter.id} '
        '(manga ${chapter.mangaId}) at page ${atPage + 1}/$pageCount: $e',
        error: e,
        stackTrace: st,
      );
      await _purge(chapter);
      await db.setChapterDeviceState(chapter.id, OfflineDeviceState.error);
      rethrow;
    }
  }

  Future<void> deleteChapter(OfflineChapter chapter) async {
    // Clear state and page rows atomically before removing files; recovery can sweep leftover files.
    await db.transaction(() async {
      await db.setChapterDeviceState(
        chapter.id,
        OfflineDeviceState.none,
        bytes: 0,
      );
      await (db.delete(
        db.offlinePages,
      )..where((t) => t.chapterId.equals(chapter.id))).go();
    });
    await store.deleteChapter(chapter.mangaId, chapter.id);
  }

  Future<void> sweepInterrupted() async {
    final stuck =
        await (db.select(db.offlineChapters)..where(
              (t) => t.deviceState.equalsValue(OfflineDeviceState.downloading),
            ))
            .get();
    for (final c in stuck) {
      await deleteChapter(c);
    }
  }

  // Failed replacements may purge staging only; preserve the committed copy.
  Future<void> _purge(OfflineChapter chapter) =>
      store.deleteStaging(chapter.mangaId, chapter.id);
}
