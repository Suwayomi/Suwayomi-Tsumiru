// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';

import '../../../../helpers/offline_test_db.dart';

GraphQLClient _dummyClient() => GraphQLClient(
      link: HttpLink('http://localhost:0'),
      cache: GraphQLCache(),
    );

/// modifyBulkChapters succeeds — mimics an online mark-read.
class _OkRepo extends MangaBookRepository {
  _OkRepo() : super(_dummyClient());
  final List<ChapterBatch> batches = [];
  @override
  Future<void> modifyBulkChapters(ChapterBatch batch) async {
    batches.add(batch);
  }
}

/// modifyBulkChapters throws — mimics an offline (unreachable-server) mark-read.
class _FailingRepo extends MangaBookRepository {
  _FailingRepo() : super(_dummyClient());
  @override
  Future<void> modifyBulkChapters(ChapterBatch batch) async {
    throw Exception('offline — mutation failed');
  }
}

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  Future<void> seedChapter(int id,
          {bool isRead = false, int lastPageRead = 0}) =>
      db.upsertChapterMetadata(
        id: id, mangaId: 1, name: 'c$id', chapterIndex: id, isRead: isRead,
        lastPageRead: lastPageRead, isBookmarked: false, serverIsDownloaded: true,
        pageCount: 30, updatedAt: DateTime(2026),
      );

  test('offline mark-read lands locally and stays queued for sync', () async {
    await seedChapter(10);
    final ok = await recordReadStateWithDependencies(
      offlineEnabled: true,
      offlineDatabase: db,
      repository: _FailingRepo(),
      chapterIds: [10],
      isRead: true,
      resetPosition: true,
    );
    expect(ok, isFalse);
    final c = (await db.chapterById(10))!;
    expect(c.isRead, isTrue);
    expect(c.readStateDirty, isTrue); // queued for pushPendingProgress
    expect(c.lastPageRead, 0);
  });

  test('online mark-read clears the flag on server success', () async {
    await seedChapter(10);
    final ok = await recordReadStateWithDependencies(
      offlineEnabled: true,
      offlineDatabase: db,
      repository: _OkRepo(),
      chapterIds: [10],
      isRead: true,
      resetPosition: true,
    );
    expect(ok, isTrue);
    final c = (await db.chapterById(10))!;
    expect(c.readStateDirty, isFalse);
    expect(c.progressDirty, isFalse);
  });

  test('mark-unread is symmetric and does not touch position', () async {
    await seedChapter(10, isRead: true, lastPageRead: 7);
    final ok = await recordReadStateWithDependencies(
      offlineEnabled: true,
      offlineDatabase: db,
      repository: _OkRepo(),
      chapterIds: [10],
      isRead: false,
    );
    expect(ok, isTrue);
    final c = (await db.chapterById(10))!;
    expect(c.isRead, isFalse);
    expect(c.lastPageRead, 7); // resetPosition:false → position untouched
  });

  test('mark-read patch carries the position reset the server expects',
      () async {
    await seedChapter(10);
    final repo = _OkRepo();
    await recordReadStateWithDependencies(
      offlineEnabled: true,
      offlineDatabase: db,
      repository: repo,
      chapterIds: [10],
      isRead: true,
      resetPosition: true,
    );
    expect(repo.batches.single.patch.isRead, isTrue);
    expect(repo.batches.single.patch.lastPageRead, 0);
  });
}
