// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import '../../../utils/logger/logger.dart';
import 'offline_database.dart';
import 'offline_page_store.dart';

/// Serializes the whole-chapter operations that must never interleave: a
/// commit, a delete, an eviction, and migration's copy-then-commit.
///
/// In-isolate and in-memory on purpose. Every one of those callers runs on the
/// main isolate — the background workers only ever fill staging — so there is
/// no cross-isolate contention to arbitrate here, and a lock file would drag
/// deletion back into the queue-wide locking this design exists to get away
/// from. The chain is per chapter, so unrelated chapters never wait on
/// each other.
class ChapterFileLock {
  ChapterFileLock._();

  static final Map<int, Future<void>> _tail = {};

  /// Run [body] with exclusive access to [chapterId]'s files and catalog rows.
  static Future<T> run<T>(int chapterId, Future<T> Function() body) {
    final prior = _tail[chapterId] ?? Future<void>.value();
    final release = Completer<void>();
    _tail[chapterId] = release.future;
    // The chain link always completes successfully — a body that throws must
    // not poison every later claim on the same chapter.
    return prior.then((_) => body()).whenComplete(() {
      if (identical(_tail[chapterId], release.future)) _tail.remove(chapterId);
      release.complete();
    });
  }

  /// Run [body] holding both chapters, claimed in id order so two transfers
  /// crossing in opposite directions can't deadlock on each other.
  static Future<T> runPair<T>(int a, int b, Future<T> Function() body) {
    if (a == b) return run(a, body);
    final first = a < b ? a : b;
    final second = a < b ? b : a;
    return run(first, () => run(second, body));
  }

  /// Test-only: tests share one process, so a chain left by one test would
  /// otherwise make the next one wait on it.
  static void resetForTest() => _tail.clear();
}

/// Why a commit didn't publish a chapter.
enum ChapterCommitResult {
  /// Staging was promoted and the catalog now lists the chapter.
  committed,

  /// No staging to commit — nothing was downloading, or it was already
  /// committed.
  noStaging,

  /// Staging is missing pages; left in place so the download can resume.
  incomplete,

  /// The chapter was deleted or re-queued under the producer. Its staging is
  /// dropped; nothing is published.
  refused,
}

/// Promote a chapter's staging directory into its final home and record it in
/// the catalog — the ONE place a download becomes visible.
///
/// Both checks that matter happen while the chapter is locked, so a delete can
/// neither slip between them nor race the rename. Beyond that only a crash can
/// separate the rename from the catalog write, and replay adopts that case (a
/// complete directory under a `queued`/`downloading` row).
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

/// [commitStagedChapter] without taking the lock — for callers already inside a
/// [ChapterFileLock] section for this chapter (recovery walks a chapter's whole
/// on-disk state under one claim, and re-entering would deadlock).
Future<ChapterCommitResult> commitStagedChapterHoldingLock({
  required OfflineDatabase db,
  required OfflinePageStore store,
  required int mangaId,
  required int chapterId,
}) async {
  final manifest = await store.readManifest(mangaId, chapterId);
  if (manifest == null) return ChapterCommitResult.noStaging;

  final row = await db.chapterById(chapterId);
  // A `none` row is a delete the user made and we must honour; a bumped
  // generation means this chapter was deleted and re-queued, so these pages
  // belong to a download nobody is waiting for any more.
  if (row == null ||
      row.deviceState == OfflineDeviceState.none ||
      manifest.generation != row.downloadGeneration) {
    await store.deleteStaging(mangaId, chapterId);
    // Any copy set aside by an interrupted replacement of this chapter is
    // unreachable once we refuse — nothing else would ever clear it.
    await store.deleteSuperseded(mangaId, chapterId);
    return ChapterCommitResult.refused;
  }

  final pages = await store.commitStaging(mangaId, chapterId);
  if (pages == null) return ChapterCommitResult.incomplete;

  await db.commitDownloadedChapter(
    chapterId: chapterId,
    pages: pages,
    downloadedAt: DateTime.now(),
  );
  logger.i('Offline: chapter $chapterId committed (${pages.length} pages)');
  return ChapterCommitResult.committed;
}

/// Walk every chapter directory on disk and settle it against its catalog row.
///
/// | on disk          | row                    | what happens                  |
/// |------------------|------------------------|-------------------------------|
/// | anything         | `none` or missing      | both directories deleted      |
/// | final, complete  | `downloaded`           | nothing                       |
/// | final, complete  | anything else          | adopted — the commit rename landed, its catalog write didn't |
/// | final, legacy    | `downloaded`           | grandfathered, trusted as-is  |
/// | final, legacy    | anything else          | cleared, so it re-downloads   |
/// | staging complete | not `none`             | committed                     |
/// | staging partial  | not `none`             | left alone, resumed later     |
///
/// Driven off the filesystem rather than the catalog: the directories that
/// exist are bounded by what has actually been downloaded, where the chapter
/// table is the size of the whole library.
Future<void> recoverChaptersOnDisk({
  required OfflineDatabase db,
  required OfflinePageStore store,
}) async {
  for (final dir in await store.chaptersOnDisk()) {
    try {
      await ChapterFileLock.run(dir.chapterId, () async {
        final row = await db.chapterById(dir.chapterId);
        // Never resurrect: a `none` row is a delete the user made, and a
        // missing row means nothing authorised these files (adoption above is
        // the one sanctioned exception, and it has already run).
        if (row == null || row.deviceState == OfflineDeviceState.none) {
          await store.deleteChapter(dir.mangaId, dir.chapterId);
          return;
        }
        // An orphaned row is a pending delete, not an interrupted download —
        // the server no longer lists this chapter and the reconcile pass will
        // evict it. Everything below treats a complete directory as a download
        // to adopt, which here would flip it back to `downloaded` and strand a
        // chapter the server deleted on the device for good.
        if (row.deviceState == OfflineDeviceState.orphaned) return;

        if (dir.hasFinal) {
          final committed = await store.inspectCommitted(
            dir.mangaId,
            dir.chapterId,
          );
          switch (committed.state) {
            case ChapterDirState.complete
                when committed.generation != row.downloadGeneration:
              // Content a delete was meant to remove but didn't (the file
              // removal is best-effort). The chapter has since been re-queued,
              // so adopting this would hand back exactly what the user deleted
              // and throw away the download that replaces it.
              logger.i(
                'Offline: dropping superseded committed chapter '
                '${dir.chapterId} (generation ${committed.generation} '
                'vs ${row.downloadGeneration})',
              );
              await store.deleteCommitted(dir.mangaId, dir.chapterId);
            case ChapterDirState.complete:
              // Already settled, or the rename landed and the catalog write
              // didn't — either way the rows are cheap to reassert.
              if (row.deviceState != OfflineDeviceState.downloaded) {
                // Measured only here — the settled case is the overwhelming
                // majority and asking for page sizes there meant a stat per
                // page of the whole downloaded library, every launch.
                await db.commitDownloadedChapter(
                  chapterId: dir.chapterId,
                  pages: await store.committedPages(dir.mangaId, dir.chapterId),
                  downloadedAt: row.downloadedAt ?? DateTime.now(),
                );
                logger.i('Offline: adopted committed chapter ${dir.chapterId}');
              }
              // Staging alongside a complete final dir is a superseded attempt,
              // and so is a copy left set aside by a kill mid-replacement.
              await store.deleteStaging(dir.mangaId, dir.chapterId);
              await store.deleteSuperseded(dir.mangaId, dir.chapterId);
              return;
            case ChapterDirState.legacy:
              if (row.deviceState == OfflineDeviceState.downloaded) {
                // Downloaded before chapters were atomic. Nothing on disk can
                // prove it whole, and re-fetching everyone's library to find
                // out is not a trade worth making — trust it.
                return;
              }
              // Interrupted under the old scheme, so its pages can't be
              // verified or safely resumed. One re-download, once, on upgrade.
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
      // One unreadable directory must not stop the rest of the library from
      // being recovered.
      logger.e('Offline: recovery skipped for chapter ${dir.chapterId}: $e');
    }
  }
}

/// Drop a chapter's unusable files and rows, leaving the state that makes the
/// downloader pick it up again.
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
