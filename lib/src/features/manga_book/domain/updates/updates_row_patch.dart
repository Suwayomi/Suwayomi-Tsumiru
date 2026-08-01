// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'package:flutter/foundation.dart'; // debugPrint

import '../chapter/chapter_model.dart';
import '../chapter/graphql/__generated__/fragment.graphql.dart';

/// A page holds 50 rows and a newly added series can be all of them, so this
/// keeps a return from the reader from bursting 50 requests at a home server.
const int kUpdatesRefreshBatchSize = 8;

/// Fetches [ids] via [fetch], [batchSize] at a time. A failing fetch is dropped
/// rather than fatal — one unreachable chapter must not sink the whole batch.
Future<List<ChapterDto>> fetchChaptersInBatches({
  required List<int> ids,
  required Future<ChapterDto?> Function(int id) fetch,
  int batchSize = kUpdatesRefreshBatchSize,
}) async {
  final fetched = <ChapterDto>[];
  for (var start = 0; start < ids.length; start += batchSize) {
    final batch = ids.sublist(start, min(start + batchSize, ids.length));
    final results = await Future.wait([
      for (final id in batch)
        fetch(id).then<ChapterDto?>(
          (c) => c,
          // Failing soft keeps one bad chapter from costing the user the rest,
          // but a swallowed error already hid a live bug here once, so say so.
          onError: (Object e, StackTrace _) {
            debugPrint('Updates row refresh failed for chapter $id: $e');
            return null;
          },
        ),
    ]);
    fetched.addAll(results.nonNulls);
  }
  return fetched;
}

/// Rewrites [rows] for [mangaId] from [chapters]; rows the fetch doesn't cover
/// keep what they had. Read state only moves forward — a lagging refetch must
/// never flip an already-read row back to unread, which was the original bug.
List<ChapterWithMangaDto> patchRowsForManga({
  required List<ChapterWithMangaDto> rows,
  required int mangaId,
  required List<ChapterDto> chapters,
}) {
  final fresh = {
    for (final chapter in chapters)
      if (chapter.mangaId == mangaId) chapter.id: chapter,
  };
  final patched = <ChapterWithMangaDto>[];
  for (final row in rows) {
    final chapter = row.mangaId == mangaId ? fresh[row.id] : null;
    patched.add(chapter == null
        ? row
        : row.copyWith(
            isRead: chapter.isRead || row.isRead,
            isBookmarked: chapter.isBookmarked,
            isDownloaded: chapter.isDownloaded,
            lastPageRead: chapter.lastPageRead,
          ));
  }
  return patched;
}
