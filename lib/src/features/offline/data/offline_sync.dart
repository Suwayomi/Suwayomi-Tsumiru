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
      for (final c in await _db.dirtyProgressChapters()) c.id: c,
    };
    for (final c in chapters) {
      final local = dirty[c.id];
      await _db.upsertChapterMetadata(
        id: c.id,
        mangaId: c.mangaId,
        name: c.name,
        chapterIndex: c.sourceOrder,
        isRead: local?.isRead ?? c.isRead,
        lastPageRead: local?.lastPageRead ?? c.lastPageRead,
        isBookmarked: c.isBookmarked,
        serverIsDownloaded: c.isDownloaded,
        pageCount: c.pageCount,
        updatedAt: now,
      );
    }
  }
}
