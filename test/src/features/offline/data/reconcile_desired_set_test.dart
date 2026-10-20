import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/reconcile_logic.dart';

OfflineChapter ch(
  int id,
  int idx, {
  bool read = false,
  bool pinned = false,
  OfflineDeviceState deviceState = OfflineDeviceState.none,
  double? chapterNumber,
  String? uploadDate,
  String? fetchedAt,
  String? name,
}) => OfflineChapter(
  id: id,
  mangaId: 1,
  name: name ?? 'c$id',
  chapterIndex: idx,
  isRead: read,
  lastPageRead: 0,
  isBookmarked: false,
  serverIsDownloaded: true,
  deviceState: deviceState,
  pageCount: 1,
  bytes: 0,
  pinned: pinned,
  downloadedAt: null,
  progressDirty: false,
  bookmarkDirty: false,
  readStateDirty: false,
  readStateManual: false,
  syncedIsRead: false,
  updatedAt: DateTime(2026),
  downloadGeneration: 0,
  serverFetchAttempts: 0,
  chapterNumber: chapterNumber,
  uploadDate: uploadDate,
  fetchedAt: fetchedAt,
);

void main() {
  final chapters = [
    ch(1, 1, read: true),
    ch(2, 2, read: true),
    ch(3, 3), // unread
    ch(4, 4), // unread
    ch(5, 5), // unread
  ];

  test('off keeps nothing (except pinned)', () {
    expect(desiredChapterIds(chapters, OfflineKeepRule.off, 3), isEmpty);
    final withPin = [...chapters, ch(9, 9, read: true, pinned: true)];
    expect(desiredChapterIds(withPin, OfflineKeepRule.off, 3), {9});
  });

  test('all keeps every chapter', () {
    expect(desiredChapterIds(chapters, OfflineKeepRule.all, 3), {
      1,
      2,
      3,
      4,
      5,
    });
  });

  test('allUnread keeps only unread', () {
    expect(desiredChapterIds(chapters, OfflineKeepRule.allUnread, 3), {
      3,
      4,
      5,
    });
  });

  test(
    'nUnread keeps the N lowest-index unread after the furthest-read position',
    () {
      expect(desiredChapterIds(chapters, OfflineKeepRule.nUnread, 2), {3, 4});
    },
  );

  test('nUnread unions pinned even when read or beyond N', () {
    final c = [...chapters, ch(1, 1, read: true, pinned: true)];
    // id 1 already present but pinned; plus next-2-unread {3,4}
    expect(desiredChapterIds(c, OfflineKeepRule.nUnread, 2), {1, 3, 4});
  });

  test('nUnread skips a permanently-errored chapter and lets the next unread '
      'chapter take its slot, instead of wasting the slot forever', () {
    // Regression: chapter 3 (lowest-index unread) can never be fetched
    // (deviceState == error). Without excluding it from the candidate pool,
    // it would occupy one of the two requested slots forever and chapter 5
    // would never get a turn — "keep 2 downloaded" would silently plateau at
    // 1 real chapter kept.
    final c = [
      ch(1, 1, read: true),
      ch(2, 2, read: true),
      ch(3, 3, deviceState: OfflineDeviceState.error), // unread, unfetchable
      ch(4, 4), // unread
      ch(5, 5), // unread
    ];
    expect(desiredChapterIds(c, OfflineKeepRule.nUnread, 2), {4, 5});
  });

  test('nUnread uses chapterNumber, not chapterIndex, for the floor: a bonus '
      'chapter added late (high sourceOrder) but numbered 0.5 is treated as '
      'narratively early and excluded once the user has read past it', () {
    // Source feed order (chapterIndex): bonus=50, ch.1=1, ch.50=2, …, ch.100=3
    // The bonus chapter was added to the source feed after ch.100 existed, so
    // the source assigned it sourceOrder=50. But its real number is 0.5.
    // After the user reads up to ch.50 (chapterNumber=50.0, floor=50.0),
    // chapterNumber-based ordering correctly sees 0.5 < 50 → don't download.
    // chapterIndex-based ordering would wrongly see 50 > 2 → would download.
    final c = [
      ch(10, 1, read: true, chapterNumber: 1.0), // ch.1, sourceOrder=1
      ch(20, 2, read: true, chapterNumber: 50.0), // ch.50, sourceOrder=2
      ch(30, 3, chapterNumber: 51.0), // ch.51, unread, ahead
      ch(40, 4, chapterNumber: 52.0), // ch.52, unread, ahead
      // Bonus chapter: added late → high sourceOrder (50), but number = 0.5
      ch(50, 50, chapterNumber: 0.5), // unread, narratively before ch.1
    ];
    // Floor by chapterNumber = 50.0. Only ch.51 (30) and ch.52 (40) are ahead.
    // The bonus ch.0.5 should NOT be included even though sourceOrder=50 > floor
    // by sourceOrder (2).
    expect(desiredChapterIds(c, OfflineKeepRule.nUnread, 2), {30, 40});
  });

  group('retainedChapterIds (what may STAY on device)', () {
    test(
      'nUnread retains downloaded UNREAD chapters behind the floor '
      '(regression: marking a far-ahead chapter read must not delete them)',
      () {
        // At ch.100 (read); 11..13 already downloaded but unread and behind the
        // furthest-read floor. The download set only wants the next unread
        // ahead of the floor, but retention must keep 11..13 so reconcile does
        // not evict chapters the reader already has.
        final c = [
          ch(11, 11, deviceState: OfflineDeviceState.downloaded),
          ch(12, 12, deviceState: OfflineDeviceState.downloaded),
          ch(13, 13, deviceState: OfflineDeviceState.downloaded),
          ch(100, 100, read: true),
          ch(101, 101), // unread, ahead
        ];
        expect(desiredChapterIds(c, OfflineKeepRule.nUnread, 2), {101});
        expect(retainedChapterIds(c, OfflineKeepRule.nUnread, 2), {
          11,
          12,
          13,
          101,
        });
      },
    );
  });

  group('sortAxis — the keep-window follows a manga\'s OWN chapter sort, not '
      'a single app-wide order', () {
    test('sortAxis: each axis ranks the keep window by its own order — the '
        'accepted risk of following a manga\'s non-narrative sort choice', () {
      // Chapter 40 has an earlier chapterIndex/chapterNumber than 30, but was
      // uploaded LATER (e.g. a re-scan or a delayed batch). Under
      // sortAxis.uploadedAt the window must follow upload order, not index.
      final c = [
        ch(10, 1, read: true, chapterNumber: 1.0, uploadDate: '1000'),
        ch(30, 2, chapterNumber: 2.0, uploadDate: '3000'), // uploaded later
        ch(40, 3, chapterNumber: 3.0, uploadDate: '2000'), // uploaded earlier
      ];
      expect(
        desiredChapterIds(
          c,
          OfflineKeepRule.nUnread,
          1,
          sortAxis: ChapterSortAxis.uploadedAt,
        ),
        {40},
        reason: 'uploadDate 2000 (chapter 40) precedes 3000 (chapter 30)',
      );

      // source follows chapterIndex even when chapterNumber disagrees.
      expect(
        desiredChapterIds(
          [
            ch(10, 1, read: true, chapterNumber: 1.0),
            ch(30, 3, chapterNumber: 90.0),
            ch(40, 4, chapterNumber: 2.0),
          ],
          OfflineKeepRule.nUnread,
          1,
          sortAxis: ChapterSortAxis.source,
        ),
        {30},
      );

      expect(
        desiredChapterIds(
          [
            ch(10, 1, read: true, chapterNumber: 1.0, fetchedAt: '1000'),
            ch(30, 2, chapterNumber: 2.0, fetchedAt: '3000'),
            ch(40, 3, chapterNumber: 3.0, fetchedAt: '2000'),
          ],
          OfflineKeepRule.nUnread,
          1,
          sortAxis: ChapterSortAxis.fetchedAt,
        ),
        {40},
      );

      final alphabetical = [
        ch(10, 1, read: true, chapterNumber: 1.0, name: 'Beta'),
        ch(20, 2, chapterNumber: 2.0, name: 'alpha'),
        ch(30, 3, chapterNumber: 3.0, name: 'Gamma'),
        ch(40, 4, chapterNumber: 4.0, name: 'delta'),
      ];
      expect(
        desiredChapterIds(
          alphabetical,
          OfflineKeepRule.nUnread,
          1,
          sortAxis: ChapterSortAxis.alphabetical,
        ),
        {40},
        reason: 'delta is the first name after the read Beta',
      );
      expect(
        desiredChapterIds(
          alphabetical,
          OfflineKeepRule.nUnread,
          5,
          sortAxis: ChapterSortAxis.alphabetical,
        ),
        {30, 40},
        reason: 'alpha sorts before the read Beta, behind the floor',
      );
    });
  });
}
