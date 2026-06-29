// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
  const OfflineSync(this._db);

  final OfflineDatabase _db;

  Future<void> syncManga(MangaDto manga) => _db.upsertMangaMetadata(
        id: manga.id,
        title: manga.title,
        thumbnailUrl: manga.thumbnailUrl,
        updatedAt: DateTime.now(),
      );

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
      // Keep a locally-changed value only while its own flag is still dirty;
      // otherwise take the server's. Tracking read-progress and bookmark
      // dirtiness separately means a server bookmark set elsewhere still
      // propagates to the device even while a read is pending up-sync, and
      // vice versa — instead of the old code pinning ALL of progress+bookmark
      // to the stale local value whenever either was dirty (#13).
      final keepProgress = local?.progressDirty ?? false;
      final keepBookmark = local?.bookmarkDirty ?? false;
      await _db.upsertChapterMetadata(
        id: c.id,
        mangaId: c.mangaId,
        name: c.name,
        chapterIndex: c.sourceOrder,
        isRead: keepProgress ? local!.isRead : c.isRead,
        lastPageRead: keepProgress ? local!.lastPageRead : c.lastPageRead,
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
  }
}
