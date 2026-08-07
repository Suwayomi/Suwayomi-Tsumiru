// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Follow-up to #308, an offline bug, so these drive the real on-device catalog
// through the real offline fallback rather than a mock.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/updates/updates_row_patch.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_read_fallback.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

import '../../../helpers/offline_test_db.dart';

const _kMangaId = 7;

/// Stands in for the server being unreachable.
class _OfflineRepo extends MangaBookRepository {
  _OfflineRepo()
      : super(GraphQLClient(
          link: HttpLink('http://localhost:0'),
          cache: GraphQLCache(),
        ));

  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async =>
      throw Exception('connection refused');
}

ChapterWithMangaDto _row({required int id, bool isRead = false}) =>
    Fragment$ChapterWithMangaDto(
      id: id,
      chapterNumber: id.toDouble(),
      fetchedAt: '0',
      isBookmarked: false,
      isDownloaded: true,
      isRead: isRead,
      lastPageRead: 0,
      lastReadAt: '0',
      mangaId: _kMangaId,
      name: 'Chapter $id',
      pageCount: 10,
      sourceOrder: id,
      uploadDate: '0',
      url: '/c/$id',
      meta: const [],
      manga: Fragment$MangaBaseDto(
        id: _kMangaId,
        genre: const [],
        inLibrary: true,
        inLibraryAt: '0',
        initialized: true,
        meta: const [],
        sourceId: '1',
        status: Enum$MangaStatus.ONGOING,
        thumbnailUrl: '/thumb',
        title: 'Series',
        unreadCount: 2,
        updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
        url: '/manga/$_kMangaId',
      ),
    );

Future<void> _putChapter(
  OfflineDatabase db, {
  required int id,
  bool isRead = false,
}) =>
    db.upsertChapterMetadata(
      id: id,
      mangaId: _kMangaId,
      name: 'Chapter $id',
      chapterIndex: id,
      isRead: isRead,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: true,
      pageCount: 10,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

/// What the Updates screen does on return, with the server down.
Future<List<ChapterDto>> _refreshOffline(
  OfflineDatabase db,
  List<int> ids,
) =>
    fetchChaptersInBatches(
      ids: ids,
      fetch: (id) => chapterMetaWithOfflineFallback(
        fetch: () async => throw Exception('connection refused'),
        db: db,
        offlineEnabled: true,
        offlineFirst: true,
        chapterId: id,
      ),
    );

void main() {
  group('Updates rows offline (#326 / #308 lineage)', () {
    test('a chapter read with the server down greys its row', () async {
      final db = testOfflineDatabase();
      addTearDown(db.close);
      await _putChapter(db, id: 1);
      await _putChapter(db, id: 2);

      // Read chapter 1 to the end, offline. This is the same call the reader
      // makes; the server write fails and the on-device catalog carries it.
      await recordReadingProgressWithDependencies(
        offlineEnabled: true,
        offlineDatabase: db,
        repository: _OfflineRepo(),
        chapterId: 1,
        lastPageRead: 9,
        isRead: true,
      );

      final chapters = await _refreshOffline(db, [1, 2]);
      final rows = patchRowsForManga(
        rows: [_row(id: 1), _row(id: 2)],
        mangaId: _kMangaId,
        chapters: chapters,
      );

      expect(rows.map((e) => e.isRead), [true, false]);
    });

    test('a chapter missing from the catalog does not hide the read one',
        () async {
      final db = testOfflineDatabase();
      addTearDown(db.close);
      await _putChapter(db, id: 1, isRead: true);

      // Chapter 2 was never downloaded, so offline it cannot be resolved at
      // all — it must not cost chapter 1 its refresh.
      final chapters = await _refreshOffline(db, [1, 2]);
      final rows = patchRowsForManga(
        rows: [_row(id: 1), _row(id: 2)],
        mangaId: _kMangaId,
        chapters: chapters,
      );

      expect(rows.map((e) => e.isRead), [true, false]);
    });
  });
}
