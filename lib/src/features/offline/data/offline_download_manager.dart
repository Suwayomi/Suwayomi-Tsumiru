// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../utils/logger/logger.dart';
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
  Future<void> downloadChapter(OfflineChapter chapter, {bool force = false}) async {
    if (!force && !chapter.serverIsDownloaded) {
      throw StateError(
          'Chapter ${chapter.id} is not downloaded server-side (server-first)');
    }
    await db.setChapterDeviceState(chapter.id, OfflineDeviceState.downloading);
    var pageCount = 0;
    var atPage = -1;
    try {
      final urls = await fetchPageUrls(chapter.id);
      pageCount = urls.length;
      logger.i('Offline: downloading chapter ${chapter.id} '
          '(manga ${chapter.mangaId}, $pageCount pages)');
      var totalBytes = 0;
      for (var i = 0; i < urls.length; i++) {
        atPage = i;
        final page = await fetchBytes(urls[i]);
        final stored = await store.writePage(
            chapter.mangaId, chapter.id, i, page.bytes, page.ext);
        totalBytes += stored.bytes;
        await db.into(db.offlinePages).insertOnConflictUpdate(
              OfflinePagesCompanion.insert(
                chapterId: chapter.id,
                pageIndex: i,
                relativePath: stored.relPath,
              ),
            );
      }
      await db.setChapterDeviceState(chapter.id, OfflineDeviceState.downloaded,
          bytes: totalBytes);
      logger.i('Offline: chapter ${chapter.id} downloaded '
          '($pageCount pages, $totalBytes bytes)');
    } catch (e, st) {
      logger.e(
          'Offline: download FAILED for chapter ${chapter.id} '
          '(manga ${chapter.mangaId}) at page ${atPage + 1}/$pageCount: $e',
          error: e,
          stackTrace: st);
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
      await db.setChapterDeviceState(chapter.id, OfflineDeviceState.none,
          bytes: 0);
      await (db.delete(db.offlinePages)
            ..where((t) => t.chapterId.equals(chapter.id)))
          .go();
    });
    await store.deleteChapter(chapter.mangaId, chapter.id);
  }

  /// On launch, reset chapters left mid-download (app killed) so they can be
  /// retried cleanly instead of being stuck `downloading` forever.
  Future<void> sweepInterrupted() async {
    final stuck = await (db.select(db.offlineChapters)
          ..where((t) =>
              t.deviceState.equalsValue(OfflineDeviceState.downloading)))
        .get();
    for (final c in stuck) {
      await deleteChapter(c);
    }
  }

  Future<void> _purge(OfflineChapter chapter) async {
    await store.deleteChapter(chapter.mangaId, chapter.id);
    await (db.delete(db.offlinePages)
          ..where((t) => t.chapterId.equals(chapter.id)))
        .go();
  }
}
