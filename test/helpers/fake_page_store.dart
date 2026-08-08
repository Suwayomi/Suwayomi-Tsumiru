// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:tsumiru/src/features/offline/data/chapter_manifest.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store.dart';

/// In-memory [OfflinePageStore] that models the real two-stage contract:
/// pages land in staging, and a chapter only becomes readable once every page
/// its manifest lists is present and the whole thing is promoted at once.
///
/// Shared by every offline test so they exercise the same publish rule the app
/// does — a stub that made [writePage] immediately visible would let a test
/// pass on a half-downloaded chapter the real store would never show.
class FakePageStore implements OfflinePageStore {
  /// Committed pages: chapterId -> pageIndex -> bytes.
  final committed = <int, Map<int, int>>{};

  /// Staged (not yet published) pages, same shape.
  final staged = <int, Map<int, int>>{};

  /// Staging manifests, as `readManifest` reports them.
  final manifests = <int, ChapterManifest>{};

  /// Manifests that rode a commit into the finished chapter — a separate map,
  /// because the real store keeps them in separate directories and conflating
  /// them let a test drive a code path production never takes.
  final committedManifests = <int, ChapterManifest>{};

  /// Extension recorded per staged page, so committed paths look real.
  final _ext = <int, Map<int, String>>{};

  /// Which manga each chapter belongs to, so the recovery scan can report it
  /// the way a directory walk would.
  final mangaOf = <int, int>{};

  /// Chapters whose files were deleted — lets tests assert cleanup happened.
  final deletedChapters = <int>[];

  /// Every page written this run, in order, including ones later superseded —
  /// tests assert on what the engine actually fetched.
  final written = <({int chapterId, int pageIndex})>[];

  /// The same writes keyed `'<chapterId>/<pageIndex>'` -> bytes.
  final pages = <String, int>{};

  /// Transfers requested, for the migration tests.
  final calls = <({int fromChapterId, int toChapterId})>[];

  /// Source chapters whose transfer should fail, standing in for unreadable
  /// files on disk.
  Set<int> failFromChapters = const {};

  /// Set to make [commitStaging] fail the way a full disk would.
  bool failCommit = false;

  @override
  Future<void> beginChapter(
    int mangaId,
    int chapterId,
    ChapterManifest manifest,
  ) async {
    manifests[chapterId] = manifest;
    mangaOf[chapterId] = mangaId;
    staged.putIfAbsent(chapterId, () => {});
    _ext.putIfAbsent(chapterId, () => {});
  }

  @override
  Future<ChapterManifest?> readManifest(int mangaId, int chapterId) async =>
      manifests[chapterId];

  @override
  Future<Set<int>> stagedPageIndices(int mangaId, int chapterId) async =>
      (staged[chapterId] ?? const {}).keys.toSet();

  @override
  Future<({String relPath, int bytes})> writePage(
    int mangaId,
    int chapterId,
    int pageIndex,
    List<int> bytes,
    String ext,
  ) async {
    staged.putIfAbsent(chapterId, () => {})[pageIndex] = bytes.length;
    _ext.putIfAbsent(chapterId, () => {})[pageIndex] = ext;
    written.add((chapterId: chapterId, pageIndex: pageIndex));
    pages['$chapterId/$pageIndex'] = bytes.length;
    return (
      relPath: '$mangaId/$chapterId.part/$pageIndex.$ext',
      bytes: bytes.length,
    );
  }

  @override
  Future<List<CommittedPage>?> commitStaging(int mangaId, int chapterId) async {
    if (failCommit) throw Exception('commit failed');
    final manifest = manifests[chapterId];
    if (manifest == null) return null;
    final pages = staged[chapterId] ?? const {};
    if (!manifest.indices.every(pages.containsKey)) return null;
    committed[chapterId] = {for (final i in manifest.indices) i: pages[i]!};
    committedManifests[chapterId] = manifest;
    staged.remove(chapterId);
    manifests.remove(chapterId);
    return [
      for (final i in manifest.indices)
        (
          pageIndex: i,
          relPath: '$mangaId/$chapterId/$i.${_ext[chapterId]?[i] ?? 'jpg'}',
          bytes: pages[i]!,
        ),
    ]..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
  }

  @override
  Future<List<StoredChapter>> chaptersOnDisk() async {
    final ids = {...committed.keys, ...staged.keys};
    return [
      for (final id in ids)
        (
          mangaId: mangaOf[id] ?? 1,
          chapterId: id,
          hasFinal: committed.containsKey(id),
          hasStaging: staged.containsKey(id),
        ),
    ];
  }

  @override
  Future<CommittedChapter> inspectCommitted(int mangaId, int chapterId) async {
    final pages = committed[chapterId];
    if (pages == null) {
      return (state: ChapterDirState.absent, generation: 0);
    }
    final manifest = committedManifests[chapterId];
    if (manifest == null) {
      return (state: ChapterDirState.legacy, generation: 0);
    }
    return (
      state: manifest.indices.every(pages.containsKey)
          ? ChapterDirState.complete
          : ChapterDirState.incomplete,
      generation: manifest.generation,
    );
  }

  @override
  Future<List<CommittedPage>> committedPages(int mangaId, int chapterId) async {
    final pages = committed[chapterId] ?? const {};
    final manifest = committedManifests[chapterId];
    if (manifest == null) return const [];
    return [
      for (final i in manifest.indices)
        if (pages.containsKey(i))
          (
            pageIndex: i,
            relPath: '$mangaId/$chapterId/$i.${_ext[chapterId]?[i] ?? 'jpg'}',
            bytes: pages[i]!,
          ),
    ]..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
  }

  @override
  Future<int> stagedBytes(int mangaId, int chapterId) async =>
      (staged[chapterId] ?? const {}).values.fold<int>(0, (sum, b) => sum + b);

  @override
  Future<void> deleteCommitted(int mangaId, int chapterId) async {
    committed.remove(chapterId);
    committedManifests.remove(chapterId);
  }

  @override
  Future<void> deleteSuperseded(int mangaId, int chapterId) async {}

  @override
  Future<void> deleteStaging(int mangaId, int chapterId) async {
    staged.remove(chapterId);
    manifests.remove(chapterId);
  }

  @override
  Future<void> deleteChapter(int mangaId, int chapterId) async {
    deletedChapters.add(chapterId);
    committed.remove(chapterId);
    committedManifests.remove(chapterId);
    staged.remove(chapterId);
    manifests.remove(chapterId);
    _ext.remove(chapterId);
  }

  @override
  Future<ChapterManifest> stageChapterCopy(
    int fromMangaId,
    int fromChapterId,
    int toMangaId,
    int toChapterId, {
    required int generation,
  }) async {
    calls.add((fromChapterId: fromChapterId, toChapterId: toChapterId));
    if (failFromChapters.contains(fromChapterId)) {
      throw const OfflineTransferException('source unreadable');
    }
    final source = committed[fromChapterId];
    if (source == null || source.isEmpty) {
      throw const OfflineTransferException('source chapter has no files');
    }
    final indices = source.keys.toList()..sort();
    final manifest = ChapterManifest(generation: generation, indices: indices);
    manifests[toChapterId] = manifest;
    staged[toChapterId] = {...source};
    _ext[toChapterId] = {...?_ext[fromChapterId]};
    return manifest;
  }

  @override
  Future<int> chapterBytes(int mangaId, int chapterId) async =>
      (committed[chapterId] ?? const {}).values.fold<int>(
        0,
        (sum, b) => sum + b,
      );

  @override
  Future<void> clearAll() async {
    committed.clear();
    staged.clear();
    manifests.clear();
    committedManifests.clear();
    _ext.clear();
  }

  /// Forget what was written, so a test can assert on a single phase.
  void resetWrites() {
    written.clear();
    pages.clear();
  }

  /// Seed a chapter as already committed, as if a previous run had downloaded
  /// it. [legacy] omits the manifest, standing in for a directory written
  /// before chapters became atomic.
  void seedCommitted(
    int chapterId,
    Map<int, int> pageBytes, {
    bool legacy = false,
    int generation = 0,
    int mangaId = 1,
  }) {
    mangaOf[chapterId] = mangaId;
    committed[chapterId] = {...pageBytes};
    _ext[chapterId] = {for (final i in pageBytes.keys) i: 'jpg'};
    if (!legacy) {
      committedManifests[chapterId] = ChapterManifest(
        generation: generation,
        indices: pageBytes.keys.toList()..sort(),
      );
    }
  }

  /// Seed staging as if a download had been interrupted partway.
  void seedStaged(
    int chapterId,
    Map<int, int> pageBytes, {
    required List<int> indices,
    int generation = 0,
    int mangaId = 1,
  }) {
    mangaOf[chapterId] = mangaId;
    manifests[chapterId] = ChapterManifest(
      generation: generation,
      indices: indices,
    );
    staged[chapterId] = {...pageBytes};
    _ext[chapterId] = {for (final i in pageBytes.keys) i: 'jpg'};
  }
}
