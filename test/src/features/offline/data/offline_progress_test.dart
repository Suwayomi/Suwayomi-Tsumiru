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
        {required int lastPageRead,
        required bool isRead,
        bool isBookmarked = false}) =>
    Fragment$ChapterDto(
      id: id, mangaId: 1, name: 'c$id', chapterNumber: id.toDouble(),
      sourceOrder: id, isRead: isRead, isBookmarked: isBookmarked,
      isDownloaded: true,
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
    expect(c.bookmarkDirty, true); // still pending up-sync
  });

  test('down-sync applies server progress for non-dirty chapters', () async {
    await seed(6, lastPageRead: 0);
    await OfflineSync(db)
        .syncChapters([serverChapter(6, lastPageRead: 12, isRead: true)]);
    final c = await db.chapterById(6);
    expect(c!.lastPageRead, 12);
    expect(c.isRead, true);
  });

  test('down-sync applies a server bookmark even while a read is pending (#13)',
      () async {
    // Local has a pending offline READ (progressDirty) but a stale bookmark;
    // the server has since bookmarked the chapter (from another client). The
    // old code pinned ALL of progress+bookmark to the local row whenever it was
    // dirty, so the server bookmark was lost and the next up-sync clobbered it.
    await seed(8, lastPageRead: 0);
    await db.setChapterProgress(8, lastPageRead: 20, isRead: false);
    await OfflineSync(db).syncChapters(
        [serverChapter(8, lastPageRead: 0, isRead: false, isBookmarked: true)]);
    final c = await db.chapterById(8);
    expect(c!.isBookmarked, true); // server bookmark propagated, not clobbered
    expect(c.lastPageRead, 20); // pending local read preserved
    expect(c.progressDirty, true); // read still pending up-sync
    expect(c.bookmarkDirty, false); // bookmark was not a local change
  });

  test('setChapterBookmark marks bookmarkDirty, not progressDirty', () async {
    await seed(9);
    await db.setChapterBookmark(9, true);
    final c = await db.chapterById(9);
    expect(c!.bookmarkDirty, true);
    expect(c.progressDirty, false); // independent of read-progress dirtiness
    expect((await db.dirtyChapters()).map((e) => e.id), [9]);
    await db.clearBookmarkDirty(9);
    expect(await db.dirtyChapters(), isEmpty);
  });

  test('clearProgressDirtyIfUnchanged keeps the flag when a newer write landed',
      () async {
    await seed(10);
    await db.setChapterProgress(10, lastPageRead: 5, isRead: false);
    // A newer local write arrives (e.g. during the up-sync push).
    await db.setChapterProgress(10, lastPageRead: 9, isRead: false);
    // Clearing with the OLD pushed values must NOT mark the newer row clean.
    await db.clearProgressDirtyIfUnchanged(10, lastPageRead: 5);
    final c = await db.chapterById(10);
    expect(c!.progressDirty, true); // newer write still pending up-sync
    expect(c.lastPageRead, 9);
    // Clearing with the CURRENT values clears it.
    await db.clearProgressDirtyIfUnchanged(10, lastPageRead: 9);
    expect((await db.chapterById(10))!.progressDirty, false);
  });

  test('partial write dirties position only; completion dirties both', () async {
    await seed(5);
    await db.setChapterProgress(5, lastPageRead: 4, isRead: null);
    var c = (await db.chapterById(5))!;
    expect(c.progressDirty, isTrue);
    expect(c.readStateDirty, isFalse);
    await db.setChapterProgress(5, lastPageRead: 0, isRead: true);
    c = (await db.chapterById(5))!;
    expect(c.readStateDirty, isTrue);
    expect(c.isRead, isTrue);
  });

  test('setChapterReadState writes isRead + readStateDirty, not position',
      () async {
    await seed(5);
    await db.setChapterProgress(5, lastPageRead: 4, isRead: null);
    await db.clearProgressDirtyIfUnchanged(5, lastPageRead: 4);
    await db.setChapterReadState(5, true);
    final c = (await db.chapterById(5))!;
    expect(c.isRead, isTrue);
    expect(c.readStateDirty, isTrue);
    expect(c.progressDirty, isFalse);
    expect(c.lastPageRead, 4);
  });

  test('read-state clear-if-unchanged mirrors bookmark race guard', () async {
    await seed(5);
    await db.setChapterReadState(5, true);
    await db.clearReadStateDirtyIfUnchanged(5, isRead: false); // mismatch
    expect((await db.chapterById(5))!.readStateDirty, isTrue);
    await db.clearReadStateDirtyIfUnchanged(5, isRead: true); // match
    expect((await db.chapterById(5))!.readStateDirty, isFalse);
  });

  test('dirtyChapters includes read-state-only-dirty rows', () async {
    await seed(5);
    await db.setChapterReadState(5, true);
    expect((await db.dirtyChapters()).map((e) => e.id), contains(5));
  });
}
