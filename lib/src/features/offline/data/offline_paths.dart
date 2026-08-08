// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:path/path.dart' as p;

import 'chapter_manifest.dart';

/// Resolves on-device offline storage paths.
///
/// Only **relative** paths are ever persisted (in the drift catalog). The
/// absolute [baseDir] — `getApplicationSupportDirectory()/offline` — is resolved
/// fresh at runtime, because iOS rewrites the app container path across installs
/// and restores, so a persisted absolute path would dangle.
///
/// Relative paths always use forward slashes so they're stable across platforms;
/// [absolute] converts them to a native path under [baseDir].
class OfflinePaths {
  const OfflinePaths(this.baseDir);

  /// Absolute base directory for all offline files (app-private, not the OS
  /// cache dir). Injected so the path logic is testable without path_provider.
  final String baseDir;

  /// `<mangaId>/<chapterId>` — the directory a chapter's page files live in.
  /// A chapter only ever appears here complete: downloads accumulate in
  /// [chapterStagingDirRel] and are promoted with a single directory rename.
  String chapterDirRel(int mangaId, int chapterId) => '$mangaId/$chapterId';

  /// `<mangaId>/<chapterId>/<NNN>.<ext>` — a single page file, zero-padded to 3.
  String pageRel(int mangaId, int chapterId, int pageIndex, String ext) =>
      '${chapterDirRel(mangaId, chapterId)}/'
      '${pageIndex.toString().padLeft(3, '0')}.$ext';

  /// `<mangaId>/<chapterId>.part` — where a chapter downloads before it is
  /// committed. Chapter ids are numeric, so this can never collide with a
  /// finished chapter's directory.
  String chapterStagingDirRel(int mangaId, int chapterId) =>
      '$mangaId/$chapterId.part';

  /// A page file inside staging — same `<NNN>.<ext>` naming as the final dir,
  /// so committing is a rename of the directory and nothing else.
  String stagingPageRel(
    int mangaId,
    int chapterId,
    int pageIndex,
    String ext,
  ) =>
      '${chapterStagingDirRel(mangaId, chapterId)}/'
      '${pageIndex.toString().padLeft(3, '0')}.$ext';

  /// The manifest describing what a complete download of this chapter looks
  /// like. Written into staging before any page.
  String stagingManifestRel(int mangaId, int chapterId) =>
      '${chapterStagingDirRel(mangaId, chapterId)}/$kChapterManifestName';

  /// `covers/<mangaId>.<ext>` — a manga's cached cover.
  String coverRel(int mangaId, String ext) => 'covers/$mangaId.$ext';

  /// Resolve a stored (forward-slash) relative path to a native absolute path
  /// under [baseDir].
  String absolute(String relPath) =>
      p.joinAll([baseDir, ...p.posix.split(relPath)]);
}
