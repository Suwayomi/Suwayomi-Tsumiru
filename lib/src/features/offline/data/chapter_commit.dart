// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import '../../../utils/logger/logger.dart';
import 'offline_database.dart';
import 'offline_page_store.dart';

/// Serializes per-chapter commit, deletion, eviction, and transfer on the main isolate.
/// Background workers write staging only; this lock does not arbitrate between isolates.
class ChapterFileLock {
  ChapterFileLock._();

  static final Map<int, Future<void>> _tail = {};

  static Future<T> run<T>(int chapterId, Future<T> Function() body) {
    final prior = _tail[chapterId] ?? Future<void>.value();
    final release = Completer<void>();
    _tail[chapterId] = release.future;
    // Failed bodies must not poison later claims on the chapter.
    return prior.then((_) => body()).whenComplete(() {
      if (identical(_tail[chapterId], release.future)) _tail.remove(chapterId);
      release.complete();
    });
  }

  /// Claims in id order to prevent deadlocks between opposing transfers.
  static Future<T> runPair<T>(int a, int b, Future<T> Function() body) {
    if (a == b) return run(a, body);
    final first = a < b ? a : b;
    final second = a < b ? b : a;
    return run(first, () => run(second, body));
  }

  static void resetForTest() => _tail.clear();
}

enum ChapterCommitResult {
  committed,

  noStaging,

  /// Staging remains available for resume.
  incomplete,

  /// Deleted or re-queued; staging is discarded.
  refused,
}

/// Publishes under the chapter lock; recovery adopts a rename interrupted before the catalog write.
Future<ChapterCommitResult> commitStagedChapter({
  required OfflineDatabase db,
  required OfflinePageStore store,
  required int mangaId,
  required int chapterId,
}) => ChapterFileLock.run(
  chapterId,
  () => commitStagedChapterHoldingLock(
    db: db,
    store: store,
    mangaId: mangaId,
    chapterId: chapterId,
  ),
);

/// Caller must hold [ChapterFileLock]; re-entering it would deadlock.
Future<ChapterCommitResult> commitStagedChapterHoldingLock({
  required OfflineDatabase db,
  required OfflinePageStore store,
  required int mangaId,
  required int chapterId,
}) async {
  final manifest = await store.readManifest(mangaId, chapterId);
  if (manifest == null) return ChapterCommitResult.noStaging;

  final row = await db.chapterById(chapterId);
  // Deleted rows and older generations must never publish their staging.
  if (row == null ||
      row.deviceState == OfflineDeviceState.none ||
      manifest.generation != row.downloadGeneration) {
    await store.deleteStaging(mangaId, chapterId);
    await store.deleteSuperseded(mangaId, chapterId);
    return ChapterCommitResult.refused;
  }

  final pages = await store.commitStaging(mangaId, chapterId);
  // The catalog cannot publish a chapter with no pages.
  if (pages == null || pages.isEmpty) return ChapterCommitResult.incomplete;

  await db.commitDownloadedChapter(
    chapterId: chapterId,
    pages: pages,
    downloadedAt: DateTime.now(),
  );
  logger.i('Offline: chapter $chapterId committed (${pages.length} pages)');
  return ChapterCommitResult.committed;
}

/// Recovers from filesystem entries, bounded by downloaded content rather than library size.
/// Deleted rows are removed; complete directories are adopted; partial staging resumes later.
Future<void> recoverChaptersOnDisk({
  required OfflineDatabase db,
  required OfflinePageStore store,
}) async {
  for (final dir in await store.chaptersOnDisk()) {
    try {
      await ChapterFileLock.run(dir.chapterId, () async {
        final row = await db.chapterById(dir.chapterId);
        // Missing or deleted rows do not authorize resurrection.
        if (row == null || row.deviceState == OfflineDeviceState.none) {
          await store.deleteChapter(dir.mangaId, dir.chapterId);
          return;
        }
        // Pending deletions must not be adopted as interrupted downloads.
        if (row.deviceState == OfflineDeviceState.orphaned ||
            row.deviceState == OfflineDeviceState.error) {
          return;
        }

        // Restore the superseded copy only without staging: verified staging is newer.
        var hasFinal = dir.hasFinal;
        if (!hasFinal && !dir.hasStaging && dir.hasSuperseded) {
          hasFinal = await store.restoreSuperseded(dir.mangaId, dir.chapterId);
          if (hasFinal) {
            logger.i(
              'Offline: restored the set-aside copy of ${dir.chapterId}',
            );
          }
        }

        if (hasFinal) {
          final committed = await store.inspectCommitted(
            dir.mangaId,
            dir.chapterId,
          );
          switch (committed.state) {
            case ChapterDirState.complete
                when committed.generation != row.downloadGeneration:
              // An older generation belongs to deleted content, even if the row was re-queued.
              logger.i(
                'Offline: dropping superseded committed chapter '
                '${dir.chapterId} (generation ${committed.generation} '
                'vs ${row.downloadGeneration})',
              );
              await store.deleteCommitted(dir.mangaId, dir.chapterId);
              // A crash after the generation bump can leave a downloaded row without valid files.
              if (row.deviceState == OfflineDeviceState.downloaded) {
                await db.transaction(() async {
                  await (db.delete(
                    db.offlinePages,
                  )..where((t) => t.chapterId.equals(dir.chapterId))).go();
                  await db.setChapterDeviceState(
                    dir.chapterId,
                    OfflineDeviceState.queued,
                    bytes: 0,
                  );
                });
              }
            case ChapterDirState.complete:
              if (row.deviceState != OfflineDeviceState.downloaded) {
                await db.commitDownloadedChapter(
                  chapterId: dir.chapterId,
                  pages: await store.committedPages(dir.mangaId, dir.chapterId),
                  downloadedAt: row.downloadedAt ?? DateTime.now(),
                );
                logger.i('Offline: adopted committed chapter ${dir.chapterId}');
              }
              await store.deleteStaging(dir.mangaId, dir.chapterId);
              await store.deleteSuperseded(dir.mangaId, dir.chapterId);
              return;
            case ChapterDirState.legacy:
              if (row.deviceState == OfflineDeviceState.downloaded) {
                // Legacy directories have no manifest; trust existing downloaded state.
                return;
              }
              // Uncommitted legacy pages cannot be verified or safely resumed.
              await _clearForRefetch(db, store, dir.mangaId, dir.chapterId);
            case ChapterDirState.incomplete:
              await _clearForRefetch(db, store, dir.mangaId, dir.chapterId);
            case ChapterDirState.absent:
              break;
          }
        }

        if (dir.hasStaging) {
          await commitStagedChapterHoldingLock(
            db: db,
            store: store,
            mangaId: dir.mangaId,
            chapterId: dir.chapterId,
          );
        }
      });
    } catch (e) {
      logger.e('Offline: recovery skipped for chapter ${dir.chapterId}: $e');
    }
  }
}

Future<void> _clearForRefetch(
  OfflineDatabase db,
  OfflinePageStore store,
  int mangaId,
  int chapterId,
) async {
  await store.deleteChapter(mangaId, chapterId);
  await db.transaction(() async {
    await (db.delete(
      db.offlinePages,
    )..where((t) => t.chapterId.equals(chapterId))).go();
    await db.setChapterDeviceState(
      chapterId,
      OfflineDeviceState.queued,
      bytes: 0,
    );
  });
}
