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

  /// Total bytes of a chapter's stored page files (for the catalog's byte
  /// count after a background download completes). 0 if nothing is stored.
  Future<int> chapterBytes(int mangaId, int chapterId);

  Future<void> clearAll() => throw UnimplementedError();
}

/// Image bytes + file extension fetched for a single page.
typedef PageBytes = ({List<int> bytes, String ext});
