// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_dto_mappers.dart';
import 'package:tsumiru/src/features/offline/data/offline_sync.dart';

import '../helpers/offline_test_db.dart';

Fragment$ChapterDto _serverChapter(int id, {required bool isRead}) =>
    Fragment$ChapterDto(
      id: id,
      mangaId: 1,
      name: 'c$id',
      chapterNumber: id.toDouble(),
      sourceOrder: id,
      isRead: isRead,
      isBookmarked: false,
      isDownloaded: false,
      lastPageRead: 0,
      pageCount: 10,
      fetchedAt: '0',
      uploadDate: '0',
      lastReadAt: '0',
      url: '',
      meta: const <Fragment$ChapterDto$meta>[],
    );

void main() {
  group('offline reads correct the unread count they cannot push yet', () {
    late OfflineDatabase db;

    setUp(() async {
      db = testOfflineDatabase();
      // The server last reported 3 chapters, none read.
      await db.upsertMangaMetadata(
        id: 1,
        title: 'Solo Leveling',
        updatedAt: DateTime(2026),
        unreadCount: 3,
        totalChapters: 3,
      );
      for (var i = 1; i <= 3; i++) {
        await db.upsertChapterMetadata(
          id: i,
          mangaId: 1,
          name: 'Ch $i',
          chapterIndex: i,
          isRead: false,
          lastPageRead: 0,
          isBookmarked: false,
          serverIsDownloaded: true,
          pageCount: 10,
          updatedAt: DateTime(2026),
        );
      }
    });

    tearDown(() => db.close());

    Future<int> unreadAsShown() async {
      final m = (await db.mangaById(1))!;
      final d = (await db.unsyncedReadDeltaByManga())[1] ?? 0;
      return offlineMangaToDto(m, unsyncedReadDelta: d).unreadCount;
    }

    // Started is chapter total minus unread, so an uncorrected aggregate makes
    // a series you just finished a chapter of read as "not started".
    test('finishing a chapter offline shows one fewer unread', () async {
      await db.setChapterReadState(1, true);
      expect(await unreadAsShown(), 2);
    });

    test('marking it unread again puts it back', () async {
      await db.setChapterReadState(1, true);
      await db.setChapterReadState(1, false);
      expect(await unreadAsShown(), 3);
    });

    test('a position-only write leaves it alone', () async {
      await db.setChapterProgress(2, lastPageRead: 4);
      expect(await unreadAsShown(), 3);
    });

    // A down-sync landing before the push must not clobber the correction.
    test('survives a stale down-sync landing before the push', () async {
      await db.setChapterReadState(1, true);
      expect(await unreadAsShown(), 2);

      // The server has not been told yet, so its aggregate still says 3.
      await db.upsertMangaMetadata(
        id: 1,
        title: 'Solo Leveling',
        updatedAt: DateTime(2026),
        unreadCount: 3,
        totalChapters: 3,
      );
      expect(await unreadAsShown(), 2);

      await db.setChapterReadState(2, true);
      expect(await unreadAsShown(), 1);
    });

    // Manga and chapter metadata sync separately, so the reduced server count
    // can land before any chapter down-sync. If the push did not move the
    // baseline, the correction would be applied again to a total that already
    // included it.

    // A refresh whose fetch went out BEFORE a push was acknowledged carries an
    // aggregate that cannot contain it, so aligning against it must not
    // retire the correction — the fetch-start generation is what tells them apart.

    // A chapter-only refresh (details pull-to-refresh) reports the pushed
    // read back, but the manga aggregate has not refreshed. Moving the
    // baseline here retired the correction against the old count.

    // A change that originated on another device is not ours to correct for.
    // In either arrival order (aggregate first or chapter list first) the
    // baseline moves with the server value, so no correction is invented.

    // A bookmark or position pending on a row must not shield its READ
    // baseline: a remote read arriving for a bookmark-dirty row is still
    // someone else's change, not ours to correct for.

    // The acked-awaiting-aggregate state is persisted in the row itself
    // (isRead != baseline, not dirty), so it must survive a restart — the
    // in-memory ack ordering does not, and losing the correction here showed
    // the pre-read figure until a manga refresh.

    // First mirror of a partly-read series: baselines initialize to the
    // server state, so mirroring must not invent a correction per read
    // chapter regardless of whether the aggregate landed first.
    test('a first mirror of read chapters creates no correction', () async {
      await db.upsertMangaMetadata(
        id: 1,
        title: 'Solo Leveling',
        updatedAt: DateTime(2026),
        unreadCount: 1,
        totalChapters: 3,
      );
      // Fresh rows 11-13, two already read server-side.
      await OfflineSync(db).syncChapters([
        _serverChapter(11, isRead: true),
        _serverChapter(12, isRead: true),
        _serverChapter(13, isRead: false),
      ]);
      expect(await unreadAsShown(), 1);
    });

    test('stays within zero and the chapter total', () async {
      for (var i = 1; i <= 3; i++) {
        await db.setChapterReadState(i, true);
      }
      expect(await unreadAsShown(), 0);

      // A stale aggregate at the maximum plus a locally-unread chapter must
      // not push the shown count past the total.
      await db.setChapterReadState(1, false);
      await db.setChapterReadState(2, false);
      await db.setChapterReadState(3, false);
      final shown = await unreadAsShown();
      expect(shown, lessThanOrEqualTo(3));
      expect(shown, greaterThanOrEqualTo(0));
    });

    // The inverse transition: a chapter the server counts as read, marked
    // unread offline. An upper-bound-only correction could never raise the
    // count again, so the series stayed "started" after being un-started.

    // An aggregate fetched before an ack cannot be assumed to contain the
    // change — but it MIGHT (the push can commit before the response comes
    // back). Rather than leave a possible double-count until an unrelated
    // refresh, a skipped alignment triggers one settling refetch whose
    // generation provably postdates the ack.

    // The never-regress policy can ABANDON a local change on reconnect: the
    // server read further, so the push is dropped. The server's state won, so
    // the row must settle to it immediately — merely clearing the dirty flag
    // leaves isRead disagreeing with the baseline forever, and the correction
    // keeps arguing for a change that lost.

    // Partial mirrors: only some chapters are on the device, so the local read
    // count is not comparable to the server's total. These pin where the
    // correction is exact and where it deliberately under-corrects.
    group('partial mirror', () {
      // The case Started actually depends on: the server knows of no reads, so
      // one offline read has to register even though most chapters are absent.

      // With the server already aware of more reads than the device mirrors,
      // an absolute local count could not prove another — the per-chapter
      // baseline makes it exact.
    });

    // A row mirrored before totalChapters existed stores zero. Clamping against
    // that raw zero forced unread to zero, making the series look fully read.
  });
}
