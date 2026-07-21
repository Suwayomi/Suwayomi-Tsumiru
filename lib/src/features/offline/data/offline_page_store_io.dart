// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'offline_page_store.dart';
import 'offline_paths.dart';

/// Native (mobile + desktop) page store: writes page files under the app-support
/// offline dir. dart:io — only constructed on native platforms (via the
/// conditional-import bootstrap), never on web.
class IoOfflinePageStore implements OfflinePageStore {
  const IoOfflinePageStore(this.paths);

  final OfflinePaths paths;

  @override
  Future<({String relPath, int bytes})> writePage(
    int mangaId,
    int chapterId,
    int pageIndex,
    List<int> bytes,
    String ext,
  ) async {
    final rel = paths.pageRel(mangaId, chapterId, pageIndex, ext);
    final abs = paths.absolute(rel);
    final file = File(abs);
    await file.parent.create(recursive: true);
    // Atomic write: stage to a .part file, then rename into place so a crash
    // mid-write never leaves a truncated page that looks complete.
    final tmp = File('$abs.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(abs);
    return (relPath: rel, bytes: bytes.length);
  }

  @override
  Future<void> deleteChapter(int mangaId, int chapterId) async {
    final dir =
        Directory(paths.absolute(paths.chapterDirRel(mangaId, chapterId)));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  @override
  Future<List<({int pageIndex, String relPath, int bytes})>> transferChapter(
    int fromMangaId,
    int fromChapterId,
    int toMangaId,
    int toChapterId, {
    required bool keepSource,
  }) async {
    final fromRel = paths.chapterDirRel(fromMangaId, fromChapterId);
    final toRel = paths.chapterDirRel(toMangaId, toChapterId);
    final fromDir = Directory(paths.absolute(fromRel));
    final toDir = Directory(paths.absolute(toRel));
    if (!await fromDir.exists()) {
      throw const OfflineTransferException('source chapter has no files');
    }

    // Fast path — a move onto a not-yet-populated target: rename the whole dir.
    if (!keepSource && !await toDir.exists()) {
      await toDir.parent.create(recursive: true);
      await fromDir.rename(toDir.path);
    } else {
      // Copy, or a move where the target dir already exists (recovery): per-file.
      await toDir.create(recursive: true);
      await for (final e in fromDir.list()) {
        if (e is! File) continue;
        final dest = p.join(toDir.path, p.basename(e.path));
        await e.copy(dest);
      }
      if (!keepSource) await fromDir.delete(recursive: true);
    }

    final pages = <({int pageIndex, String relPath, int bytes})>[];
    await for (final e in toDir.list()) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      // Page files are `<NNN>.<ext>` — index is the stem, ext preserved as-is.
      final idx = int.tryParse(p.basenameWithoutExtension(name));
      if (idx == null) continue;
      pages.add((
        pageIndex: idx,
        relPath: '$toRel/$name',
        bytes: await e.length(),
      ));
    }
    pages.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    if (pages.isEmpty) {
      throw const OfflineTransferException('no page files after transfer');
    }
    return pages;
  }

  @override
  Future<int> chapterBytes(int mangaId, int chapterId) async {
    final dir =
        Directory(paths.absolute(paths.chapterDirRel(mangaId, chapterId)));
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  @override
  Future<void> clearAll() async {
    final dir = Directory(paths.baseDir);
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      if (entity is Directory &&
          (name == 'covers' || int.tryParse(name) != null)) {
        await entity.delete(recursive: true);
      }
    }
  }
}
