// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';

import '../../../helpers/offline_test_db.dart';

GraphQLClient _dummyClient() => GraphQLClient(
      link: HttpLink('http://localhost:0'),
      cache: GraphQLCache(),
    );

/// Captures the patch sent to the server so we can assert what reading writes.
class _CapturingRepo extends MangaBookRepository {
  _CapturingRepo() : super(_dummyClient());
  ChapterChange? lastPatch;

  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {
    lastPatch = patch;
  }
}

void main() {
  group('reading forward never un-reads a chapter', () {
    test('mid-chapter write OMITS isRead from the server patch', () async {
      final repo = _CapturingRepo();
      await recordReadingProgressWithDependencies(
        offlineEnabled: false,
        offlineDatabase: null,
        repository: repo,
        chapterId: 11,
        lastPageRead: 38,
        isRead: false, // not at the last page
      );

      final json = repo.lastPatch!.toJson();
      expect(json.containsKey('isRead'), isFalse,
          reason: 'a partial read must not send isRead at all — the server '
              'keeps whatever it had, so a stale client cannot un-read it');
      expect(json['lastPageRead'], 38);
    });

    test('completing a chapter DOES send isRead: true', () async {
      final repo = _CapturingRepo();
      await recordReadingProgressWithDependencies(
        offlineEnabled: false,
        offlineDatabase: null,
        repository: repo,
        chapterId: 11,
        lastPageRead: 0,
        isRead: true, // reached the last page
      );

      final json = repo.lastPatch!.toJson();
      expect(json['isRead'], true);
    });

    test('offline: a partial read does NOT flip a read chapter to unread',
        () async {
      final db = testOfflineDatabase();
      addTearDown(db.close);
      await db.upsertChapterMetadata(
        id: 11,
        mangaId: 1,
        name: 'c11',
        chapterIndex: 11,
        isRead: true, // already finished (e.g. on another device)
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: 40,
        updatedAt: DateTime(2026),
      );

      await recordReadingProgressWithDependencies(
        offlineEnabled: true,
        offlineDatabase: db,
        repository: _CapturingRepo(),
        chapterId: 11,
        lastPageRead: 38,
        isRead: false,
      );

      final row = await db.chapterById(11);
      expect(row!.isRead, isTrue,
          reason: 'the local cache must keep the chapter read; only position '
              'updates on a partial read');
      expect(row.lastPageRead, 38);
    });
  });
}
