// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';

import '../../../../helpers/offline_test_db.dart';

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

/// putChapter can't reach the server — the airplane-mode shape.
class _UnreachableRepo extends MangaBookRepository {
  _UnreachableRepo() : super(_dummyClient());
  @override
  Future<ChapterDto?> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {
    throw const SocketException('unreachable');
  }
}

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  Future<void> seedChapter(int id) => db.upsertChapterMetadata(
    id: id,
    mangaId: 1,
    name: 'c$id',
    chapterIndex: id,
    isRead: false,
    lastPageRead: 0,
    isBookmarked: false,
    serverIsDownloaded: true,
    pageCount: 30,
    updatedAt: DateTime(2026),
  );

  test('reading offline stamps the Last Read signal locally', () async {
    await seedChapter(10);
    await db.setChapterProgress(10, lastPageRead: 5);
    final row = await db.chapterById(10);
    final stamp = int.tryParse(row!.lastReadAt ?? '');
    expect(stamp, isNotNull);
    // Epoch seconds, not millis — must sort against server-written values.
    expect(stamp!, greaterThan(1700000000));
    expect(stamp, lessThan(10000000000));
  });

  test(
    'marking read stamps Last Read; marking unread leaves it alone',
    () async {
      await seedChapter(11);
      await db.setChapterReadState(11, true);
      final read = await db.chapterById(11);
      expect(read!.lastReadAt, isNotNull);

      await db.setChapterReadState(11, false);
      final unread = await db.chapterById(11);
      expect(unread!.lastReadAt, read.lastReadAt);
    },
  );

  test('an offline-captured progress push that cannot reach the server is '
      'not an error', () async {
    await seedChapter(12);
    final result = await recordReadingProgressWithDependencies(
      offlineEnabled: true,
      offlineDatabase: db,
      repository: _UnreachableRepo(),
      chapterId: 12,
      lastPageRead: 7,
      isRead: false,
    );
    // Dirty-flagged for the next sync, so a connection failure here isn't an error.
    expect(result.hasError, isFalse);
    final row = await db.chapterById(12);
    expect(row!.lastPageRead, 7);
    expect(row.progressDirty, isTrue);
  });

  test('an online-only user still sees the failed push', () async {
    final result = await recordReadingProgressWithDependencies(
      offlineEnabled: false,
      offlineDatabase: null,
      repository: _UnreachableRepo(),
      chapterId: 13,
      lastPageRead: 7,
      isRead: false,
    );
    expect(result.hasError, isTrue);
  });
}
