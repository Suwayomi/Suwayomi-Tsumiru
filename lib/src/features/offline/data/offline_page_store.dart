// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'chapter_manifest.dart';

typedef CommittedPage = ({int pageIndex, String relPath, int bytes});

enum ChapterDirState {
  absent,

  /// No manifest; completeness is unknown, so trust the catalog state.
  legacy,

  /// Manifest present but listed pages missing.
  incomplete,

  complete,
}

/// Generation is 0 for manifests that predate generation tracking.
typedef CommittedChapter = ({ChapterDirState state, int generation});

typedef StoredChapter = ({
  int mangaId,
  int chapterId,
  bool hasFinal,
  bool hasStaging,
  bool hasSuperseded,
});

/// Pages remain in staging until a complete chapter is published by atomic rename.
abstract class OfflinePageStore {
  /// Call before writing pages; replaces any existing staging manifest.
  Future<void> beginChapter(
    int mangaId,
    int chapterId,
    ChapterManifest manifest,
  );

  /// Null when no usable staging manifest exists.
  Future<ChapterManifest?> readManifest(int mangaId, int chapterId);

  /// Excludes and deletes half-written .tmp files.
  Future<Set<int>> stagedPageIndices(int mangaId, int chapterId);

  /// Writes to staging, returning its relative path and byte count.
  Future<({String relPath, int bytes})> writePage(
    int mangaId,
    int chapterId,
    int pageIndex,
    List<int> bytes,
    String ext,
  );

  /// Atomically promotes staging; null leaves missing/incomplete staging available for resume.
  /// Byte counts include only manifest-listed pages, measured after promotion.
  Future<List<CommittedPage>?> commitStaging(int mangaId, int chapterId);

  /// Scans files on disk rather than the whole library catalog.
  Future<List<StoredChapter>> chaptersOnDisk();

  /// Inspects shape and generation without measuring page bytes.
  Future<CommittedChapter> inspectCommitted(int mangaId, int chapterId);

  Future<List<CommittedPage>> committedPages(int mangaId, int chapterId);

  Future<int> stagedBytes(int mangaId, int chapterId);

  /// Leaves staging untouched.
  Future<void> deleteCommitted(int mangaId, int chapterId);

  Future<void> deleteSuperseded(int mangaId, int chapterId);

  /// Restores a superseded copy only when no committed directory exists; reports success.
  Future<bool> restoreSuperseded(int mangaId, int chapterId);

  Future<void> deleteStaging(int mangaId, int chapterId);

  /// Removes committed files and staging.
  Future<void> deleteChapter(int mangaId, int chapterId);

  /// Copies committed pages into target staging; the caller deletes the source after target commit.
  /// A rename would lose the source if the target catalog write failed.
  Future<ChapterManifest> stageChapterCopy(
    int fromMangaId,
    int fromChapterId,
    int toMangaId,
    int toChapterId, {
    required int generation,
  }) => throw UnimplementedError();

  /// Returns 0 when nothing is stored.
  Future<int> chapterBytes(int mangaId, int chapterId);

  Future<void> clearAll() => throw UnimplementedError();
}

typedef PageBytes = ({List<int> bytes, String ext});

class OfflineTransferException implements Exception {
  const OfflineTransferException(this.message);
  final String message;
  @override
  String toString() => 'OfflineTransferException: $message';
}
