// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:collection/collection.dart';

import '../../../utils/crash/diagnostics.dart';
import '../../library/domain/category/category_model.dart';
import '../../manga_book/domain/chapter/chapter_model.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import 'offline_database.dart';
import 'webui_chapter_sort_meta.dart';

/// Metadata refreshes preserve device-managed columns; callers must guard offline availability.

class OfflineSync {
  const OfflineSync(
    this._db, {
    this.onSynced,
    this.refetchManga,
    this.taskTracker,
    this.isCurrentSession,
  });

  final Future<T> Function<T>(Future<T> Function())? taskTracker;
  final bool Function()? isCurrentSession;
  bool get _current => isCurrentSession?.call() ?? true;

  Future<T> _track<T>(Future<T> Function() action) =>
      taskTracker?.call(action) ?? action();

  final OfflineDatabase _db;
  final Future<void> Function()? onSynced;

  /// Refetches aggregates after late acknowledgements so their corrections can settle.
  final Future<MangaDto?> Function(int mangaId)? refetchManga;

  /// Capture before fetching metadata to order it against concurrent push acknowledgements.
  int get syncGeneration => _db.syncGeneration;

  Future<void> syncManga(
    MangaDto manga, {
    required int fetchedAtGen,
    bool isSettleRetry = false,
  }) => _track(
    () => _syncManga(
      manga,
      fetchedAtGen: fetchedAtGen,
      isSettleRetry: isSettleRetry,
    ),
  );

  Future<void> _syncManga(
    MangaDto manga, {
    required int fetchedAtGen,
    required bool isSettleRetry,
  }) async {
    if (!_current) return;
    // Counts and baselines must commit together to avoid double-counting after a crash.
    var skippedLateAcks = 0;
    await _db.transaction(() async {
      await _db.upsertMangaMetadata(
        id: manga.id,
        title: manga.title,
        thumbnailUrl: manga.thumbnailUrl,
        updatedAt: DateTime.now(),
        sourceId: manga.source?.id,
        sourceName: manga.source?.name,
        sourceLang: manga.source?.lang,
        sourceContentWarning: manga.source?.contentWarning.name,
        genre: manga.genre.isEmpty ? null : jsonEncode(manga.genre),
        status: manga.status.name,
        unreadCount: manga.user.unreadCount,
        downloadCount: manga.user.downloadCount,
        bookmarkCount: manga.user.bookmarkCount,
        // inLibraryAt can outlive membership; only user.inLibrary determines current membership.
        inLibraryAt: manga.user.inLibrary
            ? manga.user.inLibraryAt
            : kLibraryRemovedSentinel,
        latestFetchedAt: manga.latestFetchedChapter?.fetchedAt,
        latestUploadedAt: manga.latestUploadedChapter?.uploadDate,
        lastReadAt: manga.user.lastReadChapter?.user.lastReadAt,
        metaJson: jsonEncode({for (final e in manga.meta) e.key: e.value}),
        totalChapters: manga.chapters.totalCount,
        chapterSortMode: chapterSortAxisFromMeta(
          (key) => manga.meta.firstWhereOrNull((m) => m.key == key)?.value,
        ),
      );
      skippedLateAcks = await _db.alignSyncedReadBaseline(
        manga.id,
        upToGen: fetchedAtGen,
      );
    });
    // One later fetch settles acknowledgements that raced this aggregate.
    if (!_current) return;
    if (skippedLateAcks > 0 && !isSettleRetry && refetchManga != null) {
      final retryGen = _db.syncGeneration;
      final fresh = await refetchManga!(manga.id);
      if (!_current) return;
      if (fresh != null && fresh.user.inLibrary) {
        await _syncManga(fresh, fetchedAtGen: retryGen, isSettleRetry: true);
        return;
      }
    }
    await _db.replaceMangaCategories(
      manga.id,
      manga.categories.nodes.map((c) => c.id).toList(),
    );
    if (_current) await onSynced?.call();
  }

  static bool _keepReadBaseline(OfflineChapter? row, ChapterDto server) {
    if (row == null) return false; // first mirror initializes
    if (row.readStateDirty) return true; // push still pending
    // Preserve an acknowledged correction until its aggregate arrives; differing remote state supersedes it.
    return row.isRead != row.syncedIsRead && row.isRead == server.user.isRead;
  }

  /// Returns new remote unread-to-read transitions for the following delete-on-read reconcile.
  Future<Set<int>> syncChapters(List<ChapterDto> chapters) =>
      _track(() => _syncChapters(chapters));

  Future<Set<int>> _syncChapters(List<ChapterDto> chapters) async {
    if (!_current) return {};
    final now = DateTime.now();
    // Preserve pending local changes until up-sync succeeds.
    final dirty = {for (final c in await _db.dirtyChapters()) c.id: c};
    if (!_current) return {};
    // Persisted baselines survive a restart between acknowledgement and aggregate refresh.
    final existingRows = await _db.chaptersByIds([
      for (final c in chapters) c.id,
    ]);
    if (!_current) return {};
    final newlyRead = <int>{
      for (final c in chapters)
        if (!(dirty[c.id]?.readStateDirty ?? false) &&
            existingRows[c.id] != null &&
            !existingRows[c.id]!.isRead &&
            c.user.isRead)
          c.id,
    };
    // Mixed real and fallback chapter numbers could falsely merge distinct chapters after interruption.
    await _db.transaction(() async {
      for (final c in chapters) {
        final local = dirty[c.id];
        // Preserve each field only under its own dirty flag.
        final keepPosition = local?.progressDirty ?? false;
        final keepReadState = local?.readStateDirty ?? false;
        final keepBookmark = local?.bookmarkDirty ?? false;
        await _db.upsertChapterMetadata(
          id: c.id,
          mangaId: c.mangaId,
          name: c.name,
          chapterIndex: c.sourceOrder,
          chapterNumber: c.chapterNumber,
          scanlator: c.scanlator,
          uploadDate: c.uploadDate,
          fetchedAt: c.fetchedAt,
          isRead: keepReadState ? local!.isRead : c.user.isRead,
          syncedIsRead: _keepReadBaseline(existingRows[c.id], c)
              ? null
              : c.user.isRead,
          lastPageRead: keepPosition
              ? local!.lastPageRead
              : c.user.lastPageRead,
          isBookmarked: keepBookmark
              ? local!.isBookmarked
              : c.user.isBookmarked,
          serverIsDownloaded: c.user.isDownloaded,
          pageCount: c.pageCount,
          updatedAt: now,
          lastReadAt: c.user.lastReadAt,
        );
      }
    });

    // Orphan missing downloaded chapters only; active downloads belong to the worker.
    // An empty fetch must never orphan everything; gone rows without device content can be deleted.
    if (!_current) return {};
    final serverIdsByManga = <int, Set<int>>{};
    for (final c in chapters) {
      (serverIdsByManga[c.mangaId] ??= <int>{}).add(c.id);
    }
    for (final entry in serverIdsByManga.entries) {
      if (!_current) return {};
      final serverIds = entry.value;
      final orphanIds = <int>[];
      final staleIds = <int>[];
      for (final lc in await _db.chaptersForManga(entry.key)) {
        if (serverIds.contains(lc.id)) continue;
        switch (lc.deviceState) {
          case OfflineDeviceState.downloaded:
            orphanIds.add(lc.id);
          case OfflineDeviceState.none || OfflineDeviceState.error:
            staleIds.add(lc.id);
          case _:
        }
      }
      if (!_current) return {};
      if (orphanIds.isNotEmpty) await _db.markChaptersOrphaned(orphanIds);
      if (staleIds.isNotEmpty) {
        final dropped = await _db.deleteGoneChapters(staleIds);
        if (dropped > 0) {
          recordDiagnostic(
            '[${DateTime.now().toIso8601String()}] offline-sync: '
            'drop-gone-chapters mangaId=${entry.key} '
            'chapterIds=[${staleIds.join(',')}]\n',
          );
        }
      }
    }
    if (_current) await onSynced?.call();
    return _current ? newlyRead : {};
  }

  /// Requires a complete successful library fetch; ignores empty input.
  /// Removed series with device copies stay in On device, hidden from the offline library.
  Future<void> pruneRemovedLibraryManga(List<MangaDto> serverLibrary) =>
      _track(() => _pruneRemovedLibraryManga(serverLibrary));

  Future<void> _pruneRemovedLibraryManga(List<MangaDto> serverLibrary) async {
    if (!_current || serverLibrary.isEmpty) return;
    var serverReal = 0;
    var serverZero = 0;
    var serverEmpty = 0;
    for (final m in serverLibrary) {
      final v = m.user.inLibraryAt;
      if (v == '0') {
        serverZero++;
      } else if (v.isEmpty) {
        serverEmpty++;
      } else {
        serverReal++;
      }
    }
    recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] offline-sync: '
      'prune-server-scan total=${serverLibrary.length} real=$serverReal '
      'zero=$serverZero empty=$serverEmpty\n',
    );
    await _db.logLibraryStampCounters('before');
    // Restore present members before stamping absent ones removed.
    await _db.restoreLibraryTimestamps({
      for (final m in serverLibrary) m.id: m.user.inLibraryAt,
    });
    if (!_current) return;
    await _db.markNotInLibrary({for (final m in serverLibrary) m.id});
    if (!_current) return;
    await _db.purgeRemovedLibraryManga();
    if (!_current) return;
    await _db.logLibraryStampCounters('after');
    if (_current) await onSynced?.call();
  }

  /// Replaces the category mirror; ignores empty input to avoid wiping it after a failed fetch.
  Future<void> syncCategories(
    List<CategoryDto> categories, {
    int? defaultCategoryId = 0,
  }) => _track(
    () => _syncCategories(categories, defaultCategoryId: defaultCategoryId),
  );

  Future<void> _syncCategories(
    List<CategoryDto> categories, {
    required int? defaultCategoryId,
  }) async {
    if (!_current || categories.isEmpty) return;
    // Overlapping syncs must not interleave an older upsert after a newer prune.
    await _db.transaction(() async {
      for (final cat in categories) {
        await _db.upsertCategory(
          cat.id,
          cat.name,
          cat.order,
          isHidden: cat.isHidden,
          isDefaultCategory: cat.id == defaultCategoryId,
          autoAdd: cat.defaultCategory,
        );
      }
      await _db.pruneRemovedCategories({for (final c in categories) c.id});
    });
    if (_current) await onSynced?.call();
  }
}
