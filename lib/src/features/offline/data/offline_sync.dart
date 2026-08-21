// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import '../../library/domain/category/category_model.dart';
import '../../manga_book/domain/chapter/chapter_model.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import 'offline_database.dart';

/// Mirrors server metadata into the offline catalog during normal online use.
///
/// Maps GraphQL DTOs onto the catalog's metadata upserts, which deliberately
/// preserve device-managed columns (deviceState, bytes, thumbnailRelPath) — so
/// a re-sync never clobbers what the user has downloaded. Called online only;
/// a no-op offline (the caller guards via [offlineSyncProvider] being null).
class OfflineSync {
  const OfflineSync(this._db, {this.onSynced, this.refetchManga});

  final OfflineDatabase _db;
  final Future<void> Function()? onSynced;

  /// Fetches one manga's fresh counts. Used when an alignment had to skip
  /// late-acked corrections: a refetch whose generation postdates those acks
  /// provably covers them, so the count settles within one round-trip instead
  /// of waiting for whenever the next refresh happens to run.
  final Future<MangaDto?> Function(int mangaId)? refetchManga;

  /// Capture before issuing the fetch whose result will be passed to
  /// [syncManga] or [syncChapters] — it is how the sync layer orders that
  /// fetch against concurrent push acknowledgements.
  int get syncGeneration => _db.syncGeneration;

  Future<void> syncManga(
    MangaDto manga, {
    required int fetchedAtGen,
    bool isSettleRetry = false,
  }) async {
    // One transaction: the count and the baselines it retires are two halves
    // of the same invariant, and a kill between them would persist the new
    // count with the old corrections still live — double-counted on the next
    // offline launch.
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
        unreadCount: manga.unreadCount,
        downloadCount: manga.downloadCount,
        bookmarkCount: manga.bookmarkCount,
        inLibraryAt: manga.inLibraryAt,
        latestFetchedAt: manga.latestFetchedChapter?.fetchedAt,
        latestUploadedAt: manga.latestUploadedChapter?.uploadDate,
        lastReadAt: manga.lastReadChapter?.lastReadAt,
        metaJson: jsonEncode({for (final e in manga.meta) e.key: e.value}),
        totalChapters: manga.chapters.totalCount,
      );
      // The counts just written include every read the server knew about
      // when the fetch went out; acks landing after it keep their
      // corrections.
      skippedLateAcks = await _db.alignSyncedReadBaseline(
        manga.id,
        upToGen: fetchedAtGen,
      );
    });
    // A skipped correction means this aggregate raced a push: the server may
    // already count the change, so settle it now with a fetch that provably
    // postdates the ack rather than leaving a possible double-count until an
    // unrelated refresh. One retry only — its own skips can only come from
    // yet another concurrent push, which will trigger its own settling.
    if (skippedLateAcks > 0 && !isSettleRetry && refetchManga != null) {
      final retryGen = _db.syncGeneration;
      final fresh = await refetchManga!(manga.id);
      if (fresh != null && fresh.inLibrary) {
        await syncManga(fresh, fetchedAtGen: retryGen, isSettleRetry: true);
        return;
      }
    }
    await _db.replaceMangaCategories(
      manga.id,
      manga.categories.nodes.map((c) => c.id).toList(),
    );
    await onSynced?.call();
  }

  static bool _keepReadBaseline(OfflineChapter? row, ChapterDto server) {
    if (row == null) return false; // first mirror initializes
    if (row.readStateDirty) return true; // push still pending
    // Acked-awaiting-aggregate: the row carries a correction and the server
    // reports the value we pushed. A differing server value is newer remote
    // information and settles the row instead.
    return row.isRead != row.syncedIsRead && row.isRead == server.isRead;
  }

  /// Returns the set of chapter IDs that transitioned from unread to read
  /// during this sync (chapters the user read outside Tsumiru, e.g. in WebUI).
  /// The caller passes these to the immediately-following reconcile so that the
  /// local delete-while-reading setting fires for those chapters too.
  Future<Set<int>> syncChapters(List<ChapterDto> chapters) async {
    final now = DateTime.now();
    // Preserve read progress that was updated locally but not yet pushed to the
    // server — otherwise a down-sync would overwrite it with the stale server
    // value (the up-sync pushes it; this just stops it being lost in the gap).
    final dirty = {for (final c in await _db.dirtyChapters()) c.id: c};
    // Persisted state decides baseline handling below — it, unlike any
    // in-memory record, survives a restart between an ack and its aggregate.
    final existingRows = await _db.chaptersByIds([
      for (final c in chapters) c.id,
    ]);
    // Collect IDs whose read state flips from false to true in this sync pass.
    // Excludes locally-dirty chapters (their isRead is a pending local write,
    // not a server-originated change) and brand-new rows (no prior local state).
    final newlyRead = <int>{
      for (final c in chapters)
        if (!(dirty[c.id]?.readStateDirty ?? false) &&
            existingRows[c.id] != null &&
            !existingRows[c.id]!.isRead &&
            c.isRead)
          c.id,
    };
    // One transaction per list: an interrupted sync must not leave a manga
    // with a mix of real and index-fallback chapter numbers — a legacy row at
    // index N would falsely dedup-merge with a real chapter N.
    await _db.transaction(() async {
      for (final c in chapters) {
        final local = dirty[c.id];
        // Keep a locally-changed value only while its OWN flag is still dirty;
        // otherwise take the server's. Separate flags per field let one sync
        // in from the server while another stays pending up-sync (the ch-99
        // loop, #13).
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
          isRead: keepReadState ? local!.isRead : c.isRead,
          // Baseline handling — see OfflineChapters.syncedIsRead.
          syncedIsRead: _keepReadBaseline(existingRows[c.id], c)
              ? null
              : c.isRead,
          lastPageRead: keepPosition ? local!.lastPageRead : c.lastPageRead,
          isBookmarked: keepBookmark ? local!.isBookmarked : c.isBookmarked,
          serverIsDownloaded: c.isDownloaded,
          pageCount: c.pageCount,
          updatedAt: now,
          // Server-managed: always the server's value (drives the offline
          // "Last Read" sort). Never preserve the local one, unlike read progress.
          lastReadAt: c.lastReadAt,
        );
      }
    });

    // Device ⊆ server: a chapter the server no longer lists (deleted there) must
    // lose its on-device copy too. Mark any FULLY-DOWNLOADED local chapter
    // that's absent from this (full, per-manga) sync as orphaned — the reconcile
    // pass that runs right after a sync evicts orphaned chapters. Only the
    // `downloaded` state is orphaned: an in-flight queued/downloading chapter is
    // owned by the background worker (evicting it mid-flight would race the
    // worker, which would just re-create the row), and it will resolve on its
    // own (a deleted chapter's pages fail to fetch). Scoped to the manga(s) in
    // this sync, and a no-op for an empty list (a failed/empty fetch must never
    // orphan everything). A chapter the server lists but hasn't downloaded
    // server-side yet is still present here, so a device-on-demand download is
    // NOT orphaned (#32).
    final serverIdsByManga = <int, Set<int>>{};
    for (final c in chapters) {
      (serverIdsByManga[c.mangaId] ??= <int>{}).add(c.id);
    }
    for (final entry in serverIdsByManga.entries) {
      final serverIds = entry.value;
      final goneIds = [
        for (final lc in await _db.chaptersForManga(entry.key))
          if (!serverIds.contains(lc.id) &&
              lc.deviceState == OfflineDeviceState.downloaded)
            lc.id,
      ];
      if (goneIds.isNotEmpty) await _db.markChaptersOrphaned(goneIds);
    }
    await onSynced?.call();
    return newlyRead;
  }

  /// Removes manga that have left the server library from the offline catalog.
  /// Rows with device downloads survive (hidden from the offline library by
  /// the libraryManga membership filter, still listed in On device). An empty
  /// [serverLibrary] is ignored — a failed or empty fetch must never prune the
  /// whole catalog.
  Future<void> pruneRemovedLibraryManga(List<MangaDto> serverLibrary) async {
    if (serverLibrary.isEmpty) return;
    await _db.markNotInLibrary({for (final m in serverLibrary) m.id});
    await _db.purgeRemovedLibraryManga();
    await onSynced?.call();
  }

  /// Full mirror, not an accumulate: categories deleted on the server must
  /// stop haunting the offline tabs. Empty is ignored for the same reason as
  /// [pruneRemovedLibraryManga] — a failed fetch must never wipe the mirror.
  Future<void> syncCategories(List<CategoryDto> categories) async {
    if (categories.isEmpty) return;
    // One transaction: overlapping syncs (fired unawaited on every category
    // rebuild) must not interleave an old upsert after a newer prune.
    await _db.transaction(() async {
      for (final cat in categories) {
        await _db.upsertCategory(
          cat.id,
          cat.name,
          cat.order,
          isHidden: cat.isHidden,
        );
      }
      await _db.pruneRemovedCategories({for (final c in categories) c.id});
    });
    await onSynced?.call();
  }
}
