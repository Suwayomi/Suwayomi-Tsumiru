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

// Interrupted writes are swept, never counted as complete pages.
const String _pageTempSuffix = '.tmp';

const String _stagingSuffix = '.part';

const String _supersededSuffix = '.superseded';

class IoOfflinePageStore implements OfflinePageStore {
  const IoOfflinePageStore(this.paths);

  final OfflinePaths paths;

  Directory _staging(int mangaId, int chapterId) =>
      Directory(paths.absolute(paths.chapterStagingDirRel(mangaId, chapterId)));

  Directory _finalDir(int mangaId, int chapterId) =>
      Directory(paths.absolute(paths.chapterDirRel(mangaId, chapterId)));

  Directory _superseded(int mangaId, int chapterId) =>
      Directory('${_finalDir(mangaId, chapterId).path}$_supersededSuffix');

  @override
  Future<void> beginChapter(
    int mangaId,
    int chapterId,
    ChapterManifest manifest,
  ) async {
    await _staging(mangaId, chapterId).create(recursive: true);
    // Sync the manifest: surviving pages cannot be verified without it after a crash.
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

  // Sweep partial writes and keep only the newest extension for each page index.
  Future<Map<int, File>> _stagedPages(int mangaId, int chapterId) async {
    final dir = _staging(mangaId, chapterId);
    if (!await dir.exists()) return const {};
    final byIndex = <int, File>{};
    try {
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
    } on PathNotFoundException {
      // A concurrent delete can remove the directory between exists() and list().
      return const {};
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
    // Rename completed writes so a crash leaves a sweepable .tmp rather than a truncated page.
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

    // Preserve at least one complete copy across the swap; move an occupied destination aside first.
    final finalDir = _finalDir(mangaId, chapterId);
    final superseded = _superseded(mangaId, chapterId);
    await finalDir.parent.create(recursive: true);
    if (await finalDir.exists()) {
      await _quietDeleteDir(superseded);
      await finalDir.rename(superseded.path);
    }
    try {
      await _staging(mangaId, chapterId).rename(finalDir.path);
    } catch (_) {
      // Restore the previous copy before failure cleanup purges staging.
      if (!await finalDir.exists() && await superseded.exists()) {
        await superseded.rename(finalDir.path);
      }
      rethrow;
    }
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
    // Keep the previous copy until measurement succeeds too.
    await _quietDeleteDir(superseded);
    return pages;
  }

  @override
  Future<List<StoredChapter>> chaptersOnDisk() async {
    final found =
        <
          int,
          ({int mangaId, bool hasFinal, bool hasStaging, bool hasSuperseded})
        >{};
    final base = Directory(paths.baseDir);
    if (!await base.exists()) return const [];
    await for (final mangaEntity in base.list()) {
      if (mangaEntity is! Directory) continue;
      final mangaId = int.tryParse(p.basename(mangaEntity.path));
      if (mangaId == null) continue;
      await for (final chapterEntity in mangaEntity.list()) {
        if (chapterEntity is! Directory) continue;
        final name = p.basename(chapterEntity.path);
        final staging = name.endsWith(_stagingSuffix);
        final aside = name.endsWith(_supersededSuffix);
        final stem = staging
            ? name.substring(0, name.length - _stagingSuffix.length)
            : aside
            ? name.substring(0, name.length - _supersededSuffix.length)
            : name;
        final chapterId = int.tryParse(stem);
        if (chapterId == null) continue;
        final prior = found[chapterId];
        found[chapterId] = (
          mangaId: mangaId,
          hasFinal: (prior?.hasFinal ?? false) || (!staging && !aside),
          hasStaging: (prior?.hasStaging ?? false) || staging,
          hasSuperseded: (prior?.hasSuperseded ?? false) || aside,
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
          hasSuperseded: e.value.hasSuperseded,
        ),
    ];
  }

  @override
  Future<CommittedChapter> inspectCommitted(int mangaId, int chapterId) async {
    final dir = _finalDir(mangaId, chapterId);
    if (!await dir.exists()) {
      return (state: ChapterDirState.absent, generation: 0);
    }
    // A missing manifest identifies a legacy directory from before atomic commits.
    final manifestFile = File(p.join(dir.path, kChapterManifestName));
    if (!await manifestFile.exists()) {
      return (state: ChapterDirState.legacy, generation: 0);
    }
    final manifest = ChapterManifest.tryParse(
      await manifestFile.readAsString(),
    );
    if (manifest == null) {
      return (state: ChapterDirState.legacy, generation: 0);
    }
    final present = await _committedNames(dir);
    return (
      state: manifest.indices.every(present.containsKey)
          ? ChapterDirState.complete
          : ChapterDirState.incomplete,
      generation: manifest.generation,
    );
  }

  @override
  Future<List<CommittedPage>> committedPages(int mangaId, int chapterId) async {
    final dir = _finalDir(mangaId, chapterId);
    final manifestFile = File(p.join(dir.path, kChapterManifestName));
    if (!await manifestFile.exists()) return const [];
    final manifest = ChapterManifest.tryParse(
      await manifestFile.readAsString(),
    );
    if (manifest == null) return const [];
    final present = await _committedNames(dir);
    final rel = paths.chapterDirRel(mangaId, chapterId);
    final pages = <CommittedPage>[];
    for (final index in manifest.indices) {
      final name = present[index];
      if (name == null) continue;
      pages.add((
        pageIndex: index,
        relPath: '$rel/$name',
        bytes: await File(p.join(dir.path, name)).length(),
      ));
    }
    pages.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    return pages;
  }

  // List names without per-file stat calls; measurement is deferred until needed.
  Future<Map<int, String>> _committedNames(Directory dir) async {
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
    return byIndex;
  }

  @override
  Future<int> stagedBytes(int mangaId, int chapterId) async {
    var total = 0;
    for (final file in (await _stagedPages(mangaId, chapterId)).values) {
      total += await file.length();
    }
    return total;
  }

  @override
  Future<void> deleteCommitted(int mangaId, int chapterId) =>
      _quietDeleteDir(_finalDir(mangaId, chapterId));

  @override
  Future<void> deleteSuperseded(int mangaId, int chapterId) =>
      _quietDeleteDir(_superseded(mangaId, chapterId));

  @override
  Future<bool> restoreSuperseded(int mangaId, int chapterId) async {
    final finalDir = _finalDir(mangaId, chapterId);
    final superseded = _superseded(mangaId, chapterId);
    if (await finalDir.exists() || !await superseded.exists()) return false;
    await superseded.rename(finalDir.path);
    return true;
  }

  @override
  Future<void> deleteStaging(int mangaId, int chapterId) =>
      _quietDeleteDir(_staging(mangaId, chapterId));

  @override
  Future<void> deleteChapter(int mangaId, int chapterId) async {
    await _quietDeleteDir(_finalDir(mangaId, chapterId));
    await _quietDeleteDir(_staging(mangaId, chapterId));
    await _quietDeleteDir(_superseded(mangaId, chapterId));
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

    // Clear prior target staging so it cannot be mistaken for copied pages.
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
    }
  }

  Future<void> _quietDeleteDir(Directory dir) async {
    // Windows antivirus/indexing can briefly hold files open; retry EPERM/errno-32 deletions.
    for (var i = 0; i < 3; i++) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
        return;
      } catch (_) {
        if (i == 2) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }
}
