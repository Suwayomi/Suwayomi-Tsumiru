// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_dto_mappers.dart';
import 'package:tsumiru/src/features/offline/data/offline_sync.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

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

Fragment$MangaDto _serverManga({required int unreadCount}) => Fragment$MangaDto(
  id: 1,
  title: 'Solo Leveling',
  bookmarkCount: 0,
  chapters: Fragment$MangaDto$chapters(totalCount: 3),
  downloadCount: 0,
  genre: const [],
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
  unreadCount: unreadCount,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/1',
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

    test('finishing via reader progress counts too', () async {
      await db.setChapterProgress(2, lastPageRead: 9, isRead: true);
      expect(await unreadAsShown(), 2);
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

    test(
      'an unpushed change keeps correcting across a manga refresh',
      () async {
        await db.setChapterReadState(1, true);
        // Aggregate refreshes while the push is still pending: the row stays
        // dirty, so its baseline is kept and the correction still applies.
        await db.upsertMangaMetadata(
          id: 1,
          title: 'Solo Leveling',
          updatedAt: DateTime(2026),
          unreadCount: 3,
          totalChapters: 3,
        );
        await db.alignSyncedReadBaseline(1, upToGen: db.syncGeneration);
        expect(await unreadAsShown(), 2);
      },
    );

    // Manga and chapter metadata sync separately, so the reduced server count
    // can land before any chapter down-sync. If the push did not move the
    // baseline, the correction would be applied again to a total that already
    // included it.
    test(
      'is not applied twice when the server count catches up first',
      () async {
        await db.setChapterReadState(1, true);
        expect(await unreadAsShown(), 2);

        await db.clearReadStateDirtyIfUnchanged(1, isRead: true); // pushed
        // Still corrected: the push is known to the server, the stored count is
        // not, so dropping the correction here would show the pre-read figure.
        expect(await unreadAsShown(), 2);

        await db.upsertMangaMetadata(
          id: 1,
          title: 'Solo Leveling',
          updatedAt: DateTime(2026),
          unreadCount: 2, // library refresh now carries the read
          totalChapters: 3,
        );
        // Fetched after the ack, so the align may retire the correction.
        await db.alignSyncedReadBaseline(1, upToGen: db.syncGeneration);
        expect(await unreadAsShown(), 2);
      },
    );

    // A refresh whose fetch went out BEFORE a push was acknowledged carries an
    // aggregate that cannot contain it, so aligning against it must not
    // retire the correction — the fetch-start generation is what tells them apart.
    test(
      'a refresh fetched before the ack cannot retire the correction',
      () async {
        await db.setChapterReadState(1, true);
        final fetchGen = db.syncGeneration; // refresh fetch goes out here
        await db.clearReadStateDirtyIfUnchanged(1, isRead: true); // ack lands

        // The stale response is applied after the ack.
        await db.upsertMangaMetadata(
          id: 1,
          title: 'Solo Leveling',
          updatedAt: DateTime(2026),
          unreadCount: 3, // pre-push aggregate
          totalChapters: 3,
        );
        await db.alignSyncedReadBaseline(1, upToGen: fetchGen);
        expect(await unreadAsShown(), 2); // correction survives

        // The next refresh is fetched after the ack: it may retire it.
        await db.upsertMangaMetadata(
          id: 1,
          title: 'Solo Leveling',
          updatedAt: DateTime(2026),
          unreadCount: 2,
          totalChapters: 3,
        );
        await db.alignSyncedReadBaseline(1, upToGen: db.syncGeneration);
        expect(await unreadAsShown(), 2);
      },
    );

    // A chapter-only refresh (details pull-to-refresh) reports the pushed
    // read back, but the manga aggregate has not refreshed. Moving the
    // baseline here retired the correction against the old count.
    test('a chapter-only refresh cannot retire the correction', () async {
      await db.setChapterReadState(1, true);
      await db.clearReadStateDirtyIfUnchanged(1, isRead: true); // pushed
      expect(await unreadAsShown(), 2);

      // Server chapter list now carries the read; aggregate still says 3.
      await OfflineSync(db).syncChapters([_serverChapter(1, isRead: true)]);
      expect(await unreadAsShown(), 2); // correction survives

      // The aggregate refresh both lands the real count and retires it.
      await db.upsertMangaMetadata(
        id: 1,
        title: 'Solo Leveling',
        updatedAt: DateTime(2026),
        unreadCount: 2,
        totalChapters: 3,
      );
      await db.alignSyncedReadBaseline(1, upToGen: db.syncGeneration);
      expect(await unreadAsShown(), 2);
    });

    // A change that originated on another device is not ours to correct for.
    // In either arrival order (aggregate first or chapter list first) the
    // baseline moves with the server value, so no correction is invented.
    test(
      'a remote read arriving after the aggregate is not double-counted',
      () async {
        // Aggregate lands first: another device read ch1, count drops to 2, and
        // the alignment runs — but ch1's row still shows unread locally.
        await db.upsertMangaMetadata(
          id: 1,
          title: 'Solo Leveling',
          updatedAt: DateTime(2026),
          unreadCount: 2,
          totalChapters: 3,
        );
        await db.alignSyncedReadBaseline(1, upToGen: db.syncGeneration);
        expect(await unreadAsShown(), 2);

        // The chapter list catches up: clean row, so the baseline moves too.
        await OfflineSync(db).syncChapters([_serverChapter(1, isRead: true)]);
        expect(await unreadAsShown(), 2); // not 1
      },
    );

    // A bookmark or position pending on a row must not shield its READ
    // baseline: a remote read arriving for a bookmark-dirty row is still
    // someone else's change, not ours to correct for.
    test(
      'a bookmark-only-dirty row does not shield the read baseline',
      () async {
        await db.setChapterBookmark(1, true);
        // Aggregate already counts the remote read; chapter list catches up.
        await db.upsertMangaMetadata(
          id: 1,
          title: 'Solo Leveling',
          updatedAt: DateTime(2026),
          unreadCount: 2,
          totalChapters: 3,
        );
        await db.alignSyncedReadBaseline(1, upToGen: db.syncGeneration);
        await OfflineSync(db).syncChapters([_serverChapter(1, isRead: true)]);
        expect(await unreadAsShown(), 2); // not 1
      },
    );

    // The acked-awaiting-aggregate state is persisted in the row itself
    // (isRead != baseline, not dirty), so it must survive a restart — the
    // in-memory ack ordering does not, and losing the correction here showed
    // the pre-read figure until a manga refresh.
    test('a pushed-but-unrefreshed correction survives a restart', () async {
      await db.setChapterReadState(1, true);
      await db.clearReadStateDirtyIfUnchanged(1, isRead: true); // acked
      // "Restart": a fresh chapter-only sync confirming our value, with no
      // in-memory state assumed.
      await OfflineSync(db).syncChapters([_serverChapter(1, isRead: true)]);
      expect(await unreadAsShown(), 2); // correction still live
    });

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
    test(
      'marking a server-read chapter unread offline raises the count',
      () async {
        await db.upsertMangaMetadata(
          id: 1,
          title: 'Solo Leveling',
          updatedAt: DateTime(2026),
          unreadCount: 2,
          totalChapters: 3,
        );
        await db.upsertChapterMetadata(
          id: 1,
          mangaId: 1,
          name: 'Ch 1',
          chapterIndex: 1,
          isRead: true,
          syncedIsRead: true,
          lastPageRead: 0,
          isBookmarked: false,
          serverIsDownloaded: true,
          pageCount: 10,
          updatedAt: DateTime(2026),
        );
        expect(await unreadAsShown(), 2);
        await db.setChapterReadState(1, false);
        expect(await unreadAsShown(), 3); // and so no longer Started
      },
    );

    // An aggregate fetched before an ack cannot be assumed to contain the
    // change — but it MIGHT (the push can commit before the response comes
    // back). Rather than leave a possible double-count until an unrelated
    // refresh, a skipped alignment triggers one settling refetch whose
    // generation provably postdates the ack.
    test('a raced aggregate settles itself with one refetch', () async {
      await db.setChapterReadState(1, true);
      final fetchGen = db.syncGeneration; // refresh fetch goes out here
      await db.clearReadStateDirtyIfUnchanged(1, isRead: true); // ack lands

      var refetches = 0;
      final sync = OfflineSync(
        db,
        refetchManga: (id) async {
          refetches++;
          // The settling fetch happens after the ack: fresh count.
          return _serverManga(unreadCount: 2);
        },
      );
      // The raced response arrives carrying the pre-push count.
      await sync.syncManga(
        _serverManga(unreadCount: 3),
        fetchedAtGen: fetchGen,
      );

      expect(refetches, 1);
      final m = (await db.mangaById(1))!;
      expect(m.unreadCount, 2); // settled to the fresh count
      expect(await unreadAsShown(), 2); // and no correction left to re-apply
    });

    // The never-regress policy can ABANDON a local change on reconnect: the
    // server read further, so the push is dropped. The server's state won, so
    // the row must settle to it immediately — merely clearing the dirty flag
    // leaves isRead disagreeing with the baseline forever, and the correction
    // keeps arguing for a change that lost.
    test('an abandoned local change settles to the server state', () async {
      // Server-read chapter, marked unread offline: correction raises to 3.
      await db.upsertMangaMetadata(
        id: 1,
        title: 'Solo Leveling',
        updatedAt: DateTime(2026),
        unreadCount: 2,
        totalChapters: 3,
      );
      await db.upsertChapterMetadata(
        id: 1,
        mangaId: 1,
        name: 'Ch 1',
        chapterIndex: 1,
        isRead: true,
        syncedIsRead: true,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: 10,
        updatedAt: DateTime(2026),
      );
      await db.setChapterReadState(1, false);
      expect(await unreadAsShown(), 3);

      // Reconnect: the server still has it read, so the change is abandoned.
      await db.adoptServerReadState(
        1,
        expectedIsRead: false,
        expectedLastPageRead: 0,
        serverIsRead: true,
        serverLastPageRead: 9,
      );
      final row = (await db.chaptersForManga(1)).singleWhere((c) => c.id == 1);
      expect(row.isRead, true);
      expect(row.lastPageRead, 9);
      expect(row.readStateDirty, false);
      expect(await unreadAsShown(), 2); // back to the server's figure
    });

    test(
      'adoption is skipped if the row changed since it was examined',
      () async {
        await db.setChapterReadState(1, true);
        // A newer local write landed mid-pass: expected values no longer match.
        await db.adoptServerReadState(
          1,
          expectedIsRead: false,
          expectedLastPageRead: 0,
          serverIsRead: false,
          serverLastPageRead: 3,
        );
        final row = (await db.chaptersForManga(
          1,
        )).singleWhere((c) => c.id == 1);
        expect(row.isRead, true); // untouched
        expect(row.readStateDirty, true); // re-resolves on the next pass
      },
    );

    // Partial mirrors: only some chapters are on the device, so the local read
    // count is not comparable to the server's total. These pin where the
    // correction is exact and where it deliberately under-corrects.
    group('partial mirror', () {
      Future<int> shown(int mangaId, int chapterCount) async {
        final m = (await db.mangaById(mangaId))!;
        final d = (await db.unsyncedReadDeltaByManga())[mangaId] ?? 0;
        return offlineMangaToDto(
          m,
          chapterCount: chapterCount,
          unsyncedReadDelta: d,
        ).unreadCount;
      }

      // The case Started actually depends on: the server knows of no reads, so
      // one offline read has to register even though most chapters are absent.
      test(
        'an untouched series becomes started on the first offline read',
        () async {
          await db.upsertMangaMetadata(
            id: 10,
            title: 'Long Series',
            updatedAt: DateTime(2026),
            unreadCount: 100,
            totalChapters: 100,
          );
          await db.upsertChapterMetadata(
            id: 500,
            mangaId: 10,
            name: 'Ch 1',
            chapterIndex: 1,
            isRead: false,
            lastPageRead: 0,
            isBookmarked: false,
            serverIsDownloaded: true,
            pageCount: 10,
            updatedAt: DateTime(2026),
          );
          await db.setChapterReadState(500, true);
          expect(await shown(10, 1), 99);
          expect(100 - (await shown(10, 1)), greaterThan(0)); // Started == true
        },
      );

      // With the server already aware of more reads than the device mirrors,
      // an absolute local count could not prove another — the per-chapter
      // baseline makes it exact.
      test(
        'corrects even when the server already knows of more reads',
        () async {
          await db.upsertMangaMetadata(
            id: 11,
            title: 'Partly Read',
            updatedAt: DateTime(2026),
            unreadCount: 90,
            totalChapters: 100,
          );
          await db.upsertChapterMetadata(
            id: 600,
            mangaId: 11,
            name: 'Ch 11',
            chapterIndex: 11,
            isRead: false,
            lastPageRead: 0,
            isBookmarked: false,
            serverIsDownloaded: true,
            pageCount: 10,
            updatedAt: DateTime(2026),
          );
          await db.setChapterReadState(600, true);
          expect(await shown(11, 1), 89);
          expect(100 - (await shown(11, 1)), greaterThan(0)); // still started
        },
      );
    });

    // A row mirrored before totalChapters existed stores zero. Clamping against
    // that raw zero forced unread to zero, making the series look fully read.
    test('a legacy row with no stored total keeps its unread count', () async {
      await db.upsertMangaMetadata(
        id: 3,
        title: 'Legacy',
        updatedAt: DateTime(2026),
        unreadCount: 4,
        totalChapters: 0,
      );
      final m = (await db.mangaById(3))!;
      final dto = offlineMangaToDto(m, chapterCount: 5);
      expect(dto.unreadCount, 4);
      expect(dto.chapters.totalCount, 5);
    });

    test(
      're-reading a chapter the server already had as read is a no-op',
      () async {
        // Server already knows chapter 1 is read: 2 of 3 unread.
        await db.upsertMangaMetadata(
          id: 1,
          title: 'Solo Leveling',
          updatedAt: DateTime(2026),
          unreadCount: 2,
          totalChapters: 3,
        );
        await db.upsertChapterMetadata(
          id: 1,
          mangaId: 1,
          name: 'Ch 1',
          chapterIndex: 1,
          isRead: true,
          syncedIsRead: true,
          lastPageRead: 0,
          isBookmarked: false,
          serverIsDownloaded: true,
          pageCount: 10,
          updatedAt: DateTime(2026),
        );
        // Re-read it offline. No transition — the server already has it read.
        await db.setChapterProgress(1, lastPageRead: 9, isRead: true);
        expect(await unreadAsShown(), 2);
      },
    );
  });
}
