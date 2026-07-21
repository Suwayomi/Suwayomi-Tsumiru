// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Stores/removes a chapter's page image files on the device.
///
/// Abstract so the download orchestrator stays platform-agnostic and
/// hermetically testable; the real implementation (dart:io, under the
/// app-support dir) is provided at startup on native platforms.
abstract class OfflinePageStore {
  /// Persist one page's [bytes]; returns its stored relative path (for the
  /// catalog) and the number of bytes written.
  Future<({String relPath, int bytes})> writePage(
    int mangaId,
    int chapterId,
    int pageIndex,
    List<int> bytes,
    String ext,
  );

  /// Remove all stored files for a chapter (used on delete, and to clean up a
  /// failed/partial download).
  Future<void> deleteChapter(int mangaId, int chapterId);

  /// Transfer a chapter's page files from one manga/chapter to another (for
  /// migration: reuse downloaded bytes on the target instead of re-fetching).
  /// [keepSource] false MOVES the files (rename — instant, source left empty);
  /// true COPIES them (source kept — the Copy-not-Migrate path). Returns the
  /// moved page files as `(pageIndex, relPath, bytes)` so the catalog rows can be
  /// rewritten in one transaction. Throws if the source chapter has no files.
  Future<List<({int pageIndex, String relPath, int bytes})>> transferChapter(
    int fromMangaId,
    int fromChapterId,
    int toMangaId,
    int toChapterId, {
    required bool keepSource,
  }) =>
      throw UnimplementedError();

  /// Total bytes of a chapter's stored page files (for the catalog's byte
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
