// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
  const OfflineSync(this._db, {this.onSynced});

  final OfflineDatabase _db;
  final Future<void> Function()? onSynced;

  Future<void> syncManga(MangaDto manga) async {
    await _db.upsertMangaMetadata(
      id: manga.id,
      title: manga.title,
      thumbnailUrl: manga.thumbnailUrl,
      updatedAt: DateTime.now(),
      sourceId: manga.source?.id,
      sourceName: manga.source?.name,
      sourceLang: manga.source?.lang,
      // Deliberate legacy-server path (#138): stays on deprecated fields until a minimum server version is set.
      // ignore: deprecated_member_use_from_same_package
      sourceIsNsfw: manga.source?.isNsfw ?? false,
      status: manga.status.name,
      unreadCount: manga.unreadCount,
      downloadCount: manga.downloadCount,
      bookmarkCount: manga.bookmarkCount,
      inLibraryAt: manga.inLibraryAt,
      latestFetchedAt: manga.latestFetchedChapter?.fetchedAt,
      latestUploadedAt: manga.latestUploadedChapter?.uploadDate,
      totalChapters: manga.chapters.totalCount,
    );
    await _db.replaceMangaCategories(
      manga.id,
      manga.categories.nodes.map((c) => c.id).toList(),
    );
    await onSynced?.call();
  }

  Future<void> syncChapters(List<ChapterDto> chapters) async {
    final now = DateTime.now();
    // Preserve read progress that was updated locally but not yet pushed to the
    // server — otherwise a down-sync would overwrite it with the stale server
    // value (the up-sync pushes it; this just stops it being lost in the gap).
    final dirty = {
      for (final c in await _db.dirtyChapters()) c.id: c,
    };
    for (final c in chapters) {
      final local = dirty[c.id];
      // Keep a locally-changed value only while its OWN flag is still dirty;
      // otherwise take the server's. Position, read-state, and bookmark each
      // have their own flag, so a server change to one still lands locally
      // while another is pending up-sync — instead of the old code pinning
      // isRead to the stale local value whenever position was dirty (the ch-99
      // un-read loop), and vice versa (#13).
      final keepPosition = local?.progressDirty ?? false;
      final keepReadState = local?.readStateDirty ?? false;
      final keepBookmark = local?.bookmarkDirty ?? false;
      await _db.upsertChapterMetadata(
        id: c.id,
        mangaId: c.mangaId,
        name: c.name,
        chapterIndex: c.sourceOrder,
        isRead: keepReadState ? local!.isRead : c.isRead,
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
  }

  Future<void> syncCategories(List<CategoryDto> categories) async {
    for (final cat in categories) {
      await _db.upsertCategory(cat.id, cat.name, cat.order);
    }
    await onSynced?.call();
  }
}
