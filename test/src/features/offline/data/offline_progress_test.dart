// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_sync.dart';

import '../../../../helpers/offline_test_db.dart';

ChapterDto serverChapter(int id,
        {required int lastPageRead, required bool isRead}) =>
    Fragment$ChapterDto(
      id: id, mangaId: 1, name: 'c$id', chapterNumber: id.toDouble(),
      sourceOrder: id, isRead: isRead, isBookmarked: false, isDownloaded: true,
      lastPageRead: lastPageRead, pageCount: 30, fetchedAt: '0', uploadDate: '0',
      lastReadAt: '0', url: '', meta: const <Fragment$ChapterDto$meta>[],
    );

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  Future<void> seed(int id, {int lastPageRead = 0, bool isRead = false}) =>
      db.upsertChapterMetadata(
          id: id, mangaId: 1, name: 'c$id', chapterIndex: id, isRead: isRead,
          lastPageRead: lastPageRead, isBookmarked: false,
          serverIsDownloaded: true, pageCount: 30, updatedAt: DateTime(2026));

  test('setChapterProgress records progress + marks dirty; clear clears it',
      () async {
    await seed(5);
    await db.setChapterProgress(5, lastPageRead: 20, isRead: false);
    final c = await db.chapterById(5);
    expect(c!.lastPageRead, 20);
    expect(c.progressDirty, true);
    expect((await db.dirtyProgressChapters()).map((e) => e.id), [5]);
    await db.clearProgressDirty(5);
    expect(await db.dirtyProgressChapters(), isEmpty);
    expect((await db.chapterById(5))!.lastPageRead, 20); // value kept
  });

  test('down-sync preserves dirty local progress (no stale-server overwrite)',
      () async {
    await seed(5, lastPageRead: 16);
    await db.setChapterProgress(5, lastPageRead: 20, isRead: false); // read offline
    await OfflineSync(db)
        .syncChapters([serverChapter(5, lastPageRead: 16, isRead: false)]);
    final c = await db.chapterById(5);
    expect(c!.lastPageRead, 20); // local kept, not clobbered by server's 16
    expect(c.progressDirty, true); // still pending up-sync
  });

  test('down-sync preserves a dirty local bookmark (#33)', () async {
    await seed(7);
    await db.setChapterBookmark(7, true); // bookmarked offline, pending up-sync
    // Server still reports it un-bookmarked; a down-sync must not revert us.
    await OfflineSync(db)
        .syncChapters([serverChapter(7, lastPageRead: 0, isRead: false)]);
    final c = await db.chapterById(7);
    expect(c!.isBookmarked, true); // local kept, not clobbered
    expect(c.progressDirty, true); // still pending up-sync
  });

  test('down-sync applies server progress for non-dirty chapters', () async {
    await seed(6, lastPageRead: 0);
    await OfflineSync(db)
        .syncChapters([serverChapter(6, lastPageRead: 12, isRead: true)]);
    final c = await db.chapterById(6);
    expect(c!.lastPageRead, 12);
    expect(c.isRead, true);
  });
}
