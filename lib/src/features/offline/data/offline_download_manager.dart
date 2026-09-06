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

/// Resolves a chapter's page URLs (wraps the GraphQL fetchChapterPages call).
typedef PageUrlsFetcher = Future<List<String>> Function(int chapterId);

/// Fetches one page URL's bytes + extension (wraps the auth'd HTTP GET).
typedef PageBytesFetcher = Future<PageBytes> Function(String url);

/// Orchestrates saving a chapter's pages to the device. Platform-agnostic —
/// the page-URL resolver, byte fetcher, and file store are injected so the
/// flow is hermetically testable; real wiring (GraphQL, auth'd HTTP, dart:io,
/// free-space guard) is provided on native platforms.
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

  /// Download every page of [chapter] to the device. Requires it to be
  /// server-downloaded (product policy); on any failure, partial files/rows
  /// are removed, the chapter is marked `error`, and the error rethrows so
  /// the queue/UI can surface it.
  ///
  /// Serial and unbatched — the queue-driven downloaders are what the app
  /// actually runs. This publishes through the same staging-then-commit path
  /// they do, so a chapter it downloads is either whole or absent.
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
      // Start clean. `beginChapter` only replaces the manifest, so a previous
      // attempt's pages would survive underneath it — and the commit renames
      // the whole directory, carrying files the new manifest never listed into
      // the finished chapter.
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
      // The source answered with zero pages (chapter removed/renamed upstream,
      // for instance). commitStagedChapter refuses to publish that as
      // `downloaded`, but left unchecked the row stays `downloading` forever —
      // not `error`, so the reconciler's error-skip guard never engages and
      // this chapter is re-selected for download on every pass, looking like
      // it is stuck trying to fetch a chapter that does not exist.
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

  /// Remove a chapter's device copy entirely and reset its state.
  Future<void> deleteChapter(OfflineChapter chapter) async {
    // Flip state and drop page rows in one transaction so it serializes with
    // the coordinator's onPageStored insert: that insert either commits first
    // and is deleted here, or reads state=none and skips. Files come after —
    // reconcile sweeps an orphan file, not an orphan row.
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

  /// On launch, reset chapters left mid-download (app killed) so they can be
  /// retried cleanly instead of being stuck `downloading` forever.
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

  /// Drop what this attempt was building. Staging only: a download that failed
  /// says nothing about the copy already on the device, and wiping the chapter
  /// here turned "the re-download didn't work" into "your chapter is gone".
  /// Removing a chapter for real is [deleteChapter]'s job.
  Future<void> _purge(OfflineChapter chapter) =>
      store.deleteStaging(chapter.mangaId, chapter.id);
}
