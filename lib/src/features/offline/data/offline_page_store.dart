// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'chapter_manifest.dart';

/// One page of a committed chapter: where it now lives and how big it is.
typedef CommittedPage = ({int pageIndex, String relPath, int bytes});

/// What a chapter's final directory holds, as recovery sees it.
enum ChapterDirState {
  /// No directory at all.
  absent,

  /// A directory written before chapters became atomic, so nothing on disk
  /// says how many pages it should have. Its completeness is unknowable and a
  /// `downloaded` row is taken at its word.
  legacy,

  /// Has a manifest but is missing pages it lists — a commit that was
  /// interrupted, or files lost since.
  incomplete,

  /// Manifest present and every page it lists is there.
  complete,
}

/// A chapter's final directory and, when [state] is complete, its pages.
typedef CommittedChapter = ({ChapterDirState state, List<CommittedPage> pages});

/// Stores/removes a chapter's page image files on the device.
///
/// Chapters are written in two stages. Pages accumulate in a staging directory
/// that nothing else on the device looks at, and the chapter becomes visible in
/// one atomic directory rename once every page the manifest lists is present.
/// A chapter is therefore either absent or whole — never a partial directory
/// that a later page count would mistake for finished.
///
/// Abstract so the download orchestrator stays platform-agnostic and
/// hermetically testable; the real implementation (dart:io, under the
/// app-support dir) is provided at startup on native platforms.
abstract class OfflinePageStore {
  /// Open staging for a chapter and record what a complete download of it looks
  /// like. Call before writing any page. Safe to call on existing staging — the
  /// manifest is replaced, which is how a re-resolved page list takes effect.
  Future<void> beginChapter(
    int mangaId,
    int chapterId,
    ChapterManifest manifest,
  );

  /// The manifest staging was opened with, or null when this chapter has no
  /// (usable) staging.
  Future<ChapterManifest?> readManifest(int mangaId, int chapterId);

  /// Page indices already staged — the resume set. Half-written `.tmp` files
  /// are deleted rather than counted.
  Future<Set<int>> stagedPageIndices(int mangaId, int chapterId);

  /// Persist one page's [bytes] INTO STAGING; returns its staged relative path
  /// and the number of bytes written.
  Future<({String relPath, int bytes})> writePage(
    int mangaId,
    int chapterId,
    int pageIndex,
    List<int> bytes,
    String ext,
  );

  /// Promote staging into the chapter's final directory with a single rename,
  /// and report the pages now living there. Null when staging is missing or
  /// incomplete — the caller leaves it alone so the download can resume.
  ///
  /// Byte sizes are measured after the rename and cover only manifest-listed
  /// pages, so stray files can't inflate the catalog's accounting.
  Future<List<CommittedPage>?> commitStaging(int mangaId, int chapterId);

  /// Inspect a chapter's committed directory — what recovery reads to decide
  /// between adopting it, grandfathering it, and rebuilding it.
  Future<CommittedChapter> inspectCommitted(int mangaId, int chapterId);

  /// Discard a chapter's staging directory (delete, or a producer that lost its
  /// claim cleaning up after itself).
  Future<void> deleteStaging(int mangaId, int chapterId);

  /// Remove all stored files for a chapter — committed pages AND any staging.
  Future<void> deleteChapter(int mangaId, int chapterId);

  /// Copy a chapter's committed page files onto another manga/chapter's staging
  /// area (for migration: reuse downloaded bytes on the target instead of
  /// re-fetching), returning the manifest staging was opened with.
  ///
  /// Always a copy: a rename would destroy the source before the target's
  /// catalog write lands, and a crash in that window would leave the only copy
  /// looking like a chapter the user had deleted. The caller removes the source
  /// after the target commits.
  Future<ChapterManifest> stageChapterCopy(
    int fromMangaId,
    int fromChapterId,
    int toMangaId,
    int toChapterId, {
    required int generation,
  }) =>
      throw UnimplementedError();

  /// Total bytes of a chapter's committed page files (for the catalog's byte
  /// count after a background download completes). 0 if nothing is stored.
  Future<int> chapterBytes(int mangaId, int chapterId);

  Future<void> clearAll() => throw UnimplementedError();
}

/// Image bytes + file extension fetched for a single page.
typedef PageBytes = ({List<int> bytes, String ext});

/// A chapter's files couldn't be transferred to a migration target (missing
/// source, or nothing on disk after the transfer) — the caller falls back to a
/// server re-fetch of the target chapter.
class OfflineTransferException implements Exception {
  const OfflineTransferException(this.message);
  final String message;
  @override
  String toString() => 'OfflineTransferException: $message';
}
