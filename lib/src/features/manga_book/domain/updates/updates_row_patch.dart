// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'package:flutter/foundation.dart'; // debugPrint

import '../chapter/chapter_model.dart';
import '../chapter/graphql/__generated__/fragment.graphql.dart';

/// Limit concurrency so returning from the reader cannot send a page of 50 requests at once.
const int kUpdatesRefreshBatchSize = 8;

/// Fetches at most [batchSize] chapters concurrently; individual failures are dropped.
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

/// Unfetched rows stay unchanged; lagging refetches must not turn read rows unread.
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
    patched.add(
      chapter == null
          ? row
          : row.copyWith(
              user: row.user.copyWith(
                isRead: chapter.user.isRead || row.user.isRead,
                isBookmarked: chapter.user.isBookmarked,
                isDownloaded: chapter.user.isDownloaded,
                lastPageRead: chapter.user.lastPageRead,
              ),
            ),
    );
  }
  return patched;
}
