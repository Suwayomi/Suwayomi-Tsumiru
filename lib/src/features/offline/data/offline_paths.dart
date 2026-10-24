// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:path/path.dart' as p;

import 'chapter_manifest.dart';

/// Persist forward-slash relative paths: iOS can change the app container path on restore.
class OfflinePaths {
  const OfflinePaths(this.baseDir);

  /// App-private storage, outside the OS cache directory.
  final String baseDir;

  /// Contains only complete chapters, promoted from staging by a directory rename.
  String chapterDirRel(int mangaId, int chapterId) => '$mangaId/$chapterId';

  String pageRel(int mangaId, int chapterId, int pageIndex, String ext) =>
      '${chapterDirRel(mangaId, chapterId)}/'
      '${pageIndex.toString().padLeft(3, '0')}.$ext';

  String chapterStagingDirRel(int mangaId, int chapterId) =>
      '$mangaId/$chapterId.part';

  String stagingPageRel(
    int mangaId,
    int chapterId,
    int pageIndex,
    String ext,
  ) =>
      '${chapterStagingDirRel(mangaId, chapterId)}/'
      '${pageIndex.toString().padLeft(3, '0')}.$ext';

  /// Written into staging before any page.
  String stagingManifestRel(int mangaId, int chapterId) =>
      '${chapterStagingDirRel(mangaId, chapterId)}/$kChapterManifestName';

  String coverRel(int mangaId, String ext) => 'covers/$mangaId.$ext';

  String absolute(String relPath) =>
      p.joinAll([baseDir, ...p.posix.split(relPath)]);
}
