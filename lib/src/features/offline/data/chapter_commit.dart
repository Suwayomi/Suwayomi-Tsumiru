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
}) =>
    ChapterFileLock.run(
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
  if (row == null || row.deviceState == OfflineDeviceState.none) {
    await store.deleteStaging(mangaId, chapterId);
    return ChapterCommitResult.refused;
  }
  if (manifest.generation != row.downloadGeneration) {
    await store.deleteStaging(mangaId, chapterId);
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
