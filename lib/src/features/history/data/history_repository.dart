// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../global_providers/global_providers.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../domain/history_item.dart';
import 'graphql/__generated__/query.graphql.dart';

part 'history_repository.g.dart';

class HistoryRepository {
  const HistoryRepository(this.client);
  final GraphQLClient client;

  /// Most-recently-read chapter per manga, newest first.
  ///
  /// Fetches one bounded window (not paginated) — per-manga dedup over a
  /// chapter-ordered, live-mutable server result doesn't paginate cleanly.
  Future<List<HistoryItemDto>> getReadingHistory({
    int maxChapters = 2000,
    String? searchQuery,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final filter = Input$ChapterFilterInput(
      inLibrary: Input$BooleanFilterInput(equalTo: true),
      lastReadAt: Input$LongFilterInput(
        isNull: false,
        greaterThan:
            "0", // Ensure lastReadAt is actually set to a real timestamp
      ),
      // Chapters with actual reading progress: fully read, or past the first page.
      or: [
        Input$ChapterFilterInput(
          isRead: Input$BooleanFilterInput(equalTo: true),
        ),
        Input$ChapterFilterInput(
          lastPageRead: Input$IntFilterInput(greaterThan: 0),
        ),
      ],
      and: [
        if (fromDate != null)
          Input$ChapterFilterInput(
            lastReadAt: Input$LongFilterInput(
              greaterThanOrEqualTo: fromDate.millisecondsSinceEpoch.toString(),
            ),
          ),
        if (toDate != null)
          Input$ChapterFilterInput(
            lastReadAt: Input$LongFilterInput(
              lessThanOrEqualTo: toDate.millisecondsSinceEpoch.toString(),
            ),
          ),
        if (searchQuery.isNotBlank)
          Input$ChapterFilterInput(
            or: [
              Input$ChapterFilterInput(
                name: Input$StringFilterInput(
                  includesInsensitive: searchQuery,
                ),
              ),
              // Note: We can't search manga title directly in chapter filter
              // This will be handled in the UI layer
            ],
          ),
      ],
    );

    final order = [
      Input$ChapterOrderInput(
        by: Enum$ChapterOrderBy.LAST_READ_AT,
        byType: Enum$SortOrder.DESC,
      ),
      Input$ChapterOrderInput(
        by: Enum$ChapterOrderBy.SOURCE_ORDER,
        byType: Enum$SortOrder.DESC,
      ),
    ];

    final chapters = await client
        .query$GetReadingHistory(
          Options$Query$GetReadingHistory(
            variables: Variables$Query$GetReadingHistory(
              first: maxChapters,
              offset: 0,
              filter: filter,
              order: order,
            ),
          ),
        )
        .getData((data) => data.chapters);

    final seen = <int>{};
    final items = <HistoryItemDto>[];
    for (final chapter in chapters?.nodes ?? const <HistoryItemDto>[]) {
      // A timestamp with no read progress isn't history worth showing.
      if (!chapter.isRead && chapter.lastPageRead <= 0) continue;
      // First-seen per manga wins (server order is already newest-first).
      if (seen.add(chapter.mangaId)) items.add(chapter);
    }
    return items;
  }

  /// Get reading history for a specific manga
  Future<List<HistoryItemDto>?> getMangaReadingHistory({
    required int mangaId,
    int limit = 20,
  }) async {
    final filter = Input$ChapterFilterInput(
      mangaId: Input$IntFilterInput(equalTo: mangaId),
      lastReadAt: Input$LongFilterInput(isNull: false),
    );

    final order = [
      Input$ChapterOrderInput(
        by: Enum$ChapterOrderBy.LAST_READ_AT,
        byType: Enum$SortOrder.DESC,
      ),
    ];

    return client
        .query$GetReadingHistory(
          Options$Query$GetReadingHistory(
            variables: Variables$Query$GetReadingHistory(
              first: limit,
              filter: filter,
              order: order,
            ),
          ),
        )
        .getData((data) => data.chapters.nodes);
  }

  /// Clear all reading history (mark all chapters as unread)
  /// This is a destructive operation and should be used with caution
  Future<void> clearAllHistory() async {
    throw UnimplementedError(
      'Clearing all history requires server-side support. '
      'Please use individual chapter removal instead.',
    );
  }
}

@riverpod
HistoryRepository historyRepository(Ref ref) =>
    HistoryRepository(ref.watch(graphQlClientProvider));
