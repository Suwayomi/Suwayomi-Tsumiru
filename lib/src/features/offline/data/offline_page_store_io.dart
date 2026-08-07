// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'chapter_manifest.dart';
import 'offline_page_store.dart';
import 'offline_paths.dart';

/// Suffix of a page file still being written. Anything wearing it is junk from
/// an interrupted run and is swept, never counted.
const String _pageTempSuffix = '.tmp';

/// Directory-name suffix marking a chapter's staging area.
const String _stagingSuffix = '.part';

/// Native (mobile + desktop) page store: writes page files under the app-support
/// offline dir. dart:io — only constructed on native platforms (via the
/// conditional-import bootstrap), never on web.
class IoOfflinePageStore implements OfflinePageStore {
  const IoOfflinePageStore(this.paths);

  final OfflinePaths paths;

  Directory _staging(int mangaId, int chapterId) =>
      Directory(paths.absolute(paths.chapterStagingDirRel(mangaId, chapterId)));

  Directory _finalDir(int mangaId, int chapterId) =>
      Directory(paths.absolute(paths.chapterDirRel(mangaId, chapterId)));

  @override
  Future<void> beginChapter(
    int mangaId,
    int chapterId,
    ChapterManifest manifest,
  ) async {
    await _staging(mangaId, chapterId).create(recursive: true);
    // The one write in the whole download that still syncs. Everything else can
    // be re-fetched, but a manifest that didn't survive the crash leaves a
    // complete-looking chapter nobody can verify.
    await File(
      paths.absolute(paths.stagingManifestRel(mangaId, chapterId)),
    ).writeAsString(manifest.toJsonString(), flush: true);
  }

  @override
  Future<ChapterManifest?> readManifest(int mangaId, int chapterId) async {
    final file = File(
      paths.absolute(paths.stagingManifestRel(mangaId, chapterId)),
    );
    if (!await file.exists()) return null;
    try {
      return ChapterManifest.tryParse(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Set<int>> stagedPageIndices(int mangaId, int chapterId) async =>
      (await _stagedPages(mangaId, chapterId)).keys.toSet();

  /// Staged page files by index, after sweeping junk: half-written `.tmp`
  /// leftovers go, and when a retry landed the same page under two extensions
  /// the newest wins and the loser is deleted, so the commit rename can't carry
  /// an ambiguous pair into the final directory.
  Future<Map<int, File>> _stagedPages(int mangaId, int chapterId) async {
    final dir = _staging(mangaId, chapterId);
    if (!await dir.exists()) return const {};
    final byIndex = <int, File>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name == kChapterManifestName) continue;
      if (name.endsWith(_pageTempSuffix)) {
        await _quietDelete(entity);
        continue;
      }
      final dot = name.indexOf('.');
      if (dot <= 0) continue;
      final index = int.tryParse(name.substring(0, dot));
      if (index == null) continue;
      final existing = byIndex[index];
      if (existing == null) {
        byIndex[index] = entity;
        continue;
      }
      final keepNew = (await entity.stat()).modified.isAfter(
        (await existing.stat()).modified,
      );
      byIndex[index] = keepNew ? entity : existing;
      await _quietDelete(keepNew ? existing : entity);
    }
    return byIndex;
  }

  @override
  Future<({String relPath, int bytes})> writePage(
    int mangaId,
    int chapterId,
    int pageIndex,
    List<int> bytes,
    String ext,
  ) async {
    final rel = paths.stagingPageRel(mangaId, chapterId, pageIndex, ext);
    final abs = paths.absolute(rel);
    final file = File(abs);
    await file.parent.create(recursive: true);
    // Rename into its final name within staging so a kill mid-write leaves a
    // sweepable `.tmp`, never a truncated page that reads as complete.
    final tmp = File('$abs$_pageTempSuffix');
    await tmp.writeAsBytes(bytes);
    await tmp.rename(abs);
    return (relPath: rel, bytes: bytes.length);
  }

  @override
  Future<List<CommittedPage>?> commitStaging(int mangaId, int chapterId) async {
    final manifest = await readManifest(mangaId, chapterId);
    if (manifest == null) return null;
    final staged = await _stagedPages(mangaId, chapterId);
    if (!manifest.indices.every(staged.containsKey)) return null;

    final finalDir = _finalDir(mangaId, chapterId);
    // Rename cannot land on a populated directory, and whatever is sitting
    // there is this same chapter's earlier attempt — superseded by the verified
    // set we're about to publish.
    if (await finalDir.exists()) await finalDir.delete(recursive: true);
    await finalDir.parent.create(recursive: true);
    await _staging(mangaId, chapterId).rename(finalDir.path);

    final finalRel = paths.chapterDirRel(mangaId, chapterId);
    final pages = <CommittedPage>[];
    for (final index in manifest.indices) {
      final name = p.basename(staged[index]!.path);
      pages.add((
        pageIndex: index,
        relPath: '$finalRel/$name',
        bytes: await File(p.join(finalDir.path, name)).length(),
      ));
    }
    pages.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    return pages;
  }

  @override
  Future<List<StoredChapter>> chaptersOnDisk() async {
    final found = <int, ({int mangaId, bool hasFinal, bool hasStaging})>{};
    final base = Directory(paths.baseDir);
    if (!await base.exists()) return const [];
    await for (final mangaEntity in base.list()) {
      if (mangaEntity is! Directory) continue;
      // Skips `covers` and anything else that isn't a manga id.
      final mangaId = int.tryParse(p.basename(mangaEntity.path));
      if (mangaId == null) continue;
      await for (final chapterEntity in mangaEntity.list()) {
        if (chapterEntity is! Directory) continue;
        final name = p.basename(chapterEntity.path);
        final staging = name.endsWith(_stagingSuffix);
        final chapterId = int.tryParse(
          staging
              ? name.substring(0, name.length - _stagingSuffix.length)
              : name,
        );
        if (chapterId == null) continue;
        final prior = found[chapterId];
        found[chapterId] = (
          mangaId: mangaId,
          hasFinal: (prior?.hasFinal ?? false) || !staging,
          hasStaging: (prior?.hasStaging ?? false) || staging,
        );
      }
    }
    return [
      for (final e in found.entries)
        (
          mangaId: e.value.mangaId,
          chapterId: e.key,
          hasFinal: e.value.hasFinal,
          hasStaging: e.value.hasStaging,
        ),
    ];
  }

  @override
  Future<CommittedChapter> inspectCommitted(int mangaId, int chapterId) async {
    final dir = _finalDir(mangaId, chapterId);
    if (!await dir.exists()) {
      return (state: ChapterDirState.absent, pages: const <CommittedPage>[]);
    }
    // The manifest rides along in the commit rename, so a committed chapter
    // carries the record of what it should contain. Its absence dates the
    // directory to before atomic commits.
    final manifestFile = File(p.join(dir.path, kChapterManifestName));
    if (!await manifestFile.exists()) {
      return (state: ChapterDirState.legacy, pages: const <CommittedPage>[]);
    }
    final manifest = ChapterManifest.tryParse(
      await manifestFile.readAsString(),
    );
    if (manifest == null) {
      return (state: ChapterDirState.legacy, pages: const <CommittedPage>[]);
    }

    final byIndex = <int, String>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name == kChapterManifestName) continue;
      final dot = name.indexOf('.');
      if (dot <= 0) continue;
      final index = int.tryParse(name.substring(0, dot));
      if (index != null) byIndex[index] = name;
    }
    if (!manifest.indices.every(byIndex.containsKey)) {
      return (
        state: ChapterDirState.incomplete,
        pages: const <CommittedPage>[],
      );
    }

    final rel = paths.chapterDirRel(mangaId, chapterId);
    final pages = <CommittedPage>[];
    for (final index in manifest.indices) {
      final name = byIndex[index]!;
      pages.add((
        pageIndex: index,
        relPath: '$rel/$name',
        bytes: await File(p.join(dir.path, name)).length(),
      ));
    }
    pages.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    return (state: ChapterDirState.complete, pages: pages);
  }

  @override
  Future<void> deleteStaging(int mangaId, int chapterId) =>
      _quietDeleteDir(_staging(mangaId, chapterId));

  @override
  Future<void> deleteChapter(int mangaId, int chapterId) async {
    await _quietDeleteDir(_finalDir(mangaId, chapterId));
    await _quietDeleteDir(_staging(mangaId, chapterId));
  }

  @override
  Future<ChapterManifest> stageChapterCopy(
    int fromMangaId,
    int fromChapterId,
    int toMangaId,
    int toChapterId, {
    required int generation,
  }) async {
    final fromDir = _finalDir(fromMangaId, fromChapterId);
    if (!await fromDir.exists()) {
      throw const OfflineTransferException('source chapter has no files');
    }

    final indices = <int>[];
    final copies = <({int index, String name, File source})>[];
    await for (final entity in fromDir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name == kChapterManifestName) continue;
      final index = int.tryParse(p.basenameWithoutExtension(name));
      if (index == null) continue;
      indices.add(index);
      copies.add((index: index, name: name, source: entity));
    }
    if (copies.isEmpty) {
      throw const OfflineTransferException('no page files to transfer');
    }
    indices.sort();

    // Any half-finished staging on the target is from a download this transfer
    // supersedes; start clean so its pages can't be mistaken for copied ones.
    await deleteStaging(toMangaId, toChapterId);
    final manifest = ChapterManifest(generation: generation, indices: indices);
    await beginChapter(toMangaId, toChapterId, manifest);
    final stagingDir = _staging(toMangaId, toChapterId);
    for (final copy in copies) {
      await copy.source.copy(p.join(stagingDir.path, copy.name));
    }
    return manifest;
  }

  @override
  Future<int> chapterBytes(int mangaId, int chapterId) async {
    final dir = _finalDir(mangaId, chapterId);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File && p.basename(e.path) != kChapterManifestName) {
        total += await e.length();
      }
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

  Future<void> _quietDelete(File file) async {
    try {
      await file.delete();
    } catch (_) {
      // A locked or already-gone file is not worth failing a download over.
    }
  }

  Future<void> _quietDeleteDir(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Same: leftover bytes are dead weight, not corruption.
    }
  }
}
