import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/reconcile_logic.dart';

OfflineChapter ch(
  int id,
  int idx, {
  bool read = false,
  bool pinned = false,
  OfflineDeviceState deviceState = OfflineDeviceState.none,
}) =>
    OfflineChapter(
      id: id, mangaId: 1, name: 'c$id', chapterIndex: idx, isRead: read,
      lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
      deviceState: deviceState, pageCount: 1, bytes: 0,
      pinned: pinned, downloadedAt: null, progressDirty: false,
      bookmarkDirty: false, readStateDirty: false, readStateManual: false,
      syncedIsRead: false,
      updatedAt: DateTime(2026),
      downloadGeneration: 0,
      serverFetchAttempts: 0,
    );

void main() {
  final chapters = [
    ch(1, 1, read: true),
    ch(2, 2, read: true),
    ch(3, 3),            // unread
    ch(4, 4),            // unread
    ch(5, 5),            // unread
  ];

  test('off keeps nothing (except pinned)', () {
    expect(desiredChapterIds(chapters, OfflineKeepRule.off, 3), isEmpty);
    final withPin = [...chapters, ch(9, 9, read: true, pinned: true)];
    expect(desiredChapterIds(withPin, OfflineKeepRule.off, 3), {9});
  });

  test('all keeps every chapter', () {
    expect(desiredChapterIds(chapters, OfflineKeepRule.all, 3), {1, 2, 3, 4, 5});
  });

  test('allUnread keeps only unread', () {
    expect(desiredChapterIds(chapters, OfflineKeepRule.allUnread, 3), {3, 4, 5});
  });

  test('nUnread keeps the N lowest-index unread after the furthest-read position', () {
    expect(desiredChapterIds(chapters, OfflineKeepRule.nUnread, 2), {3, 4});
  });

  test(
    'nUnread skips unread chapters that are behind the furthest-read position',
    () {
      // User read ch.1, skipped ch.2, read ch.3 — ch.2 is unread but behind
      // the furthest-read point (index 3). nUnread should NOT download ch.2;
      // it should download ch.4 and ch.5 (the next unread chapters ahead).
      final c = [
        ch(1, 1, read: true),
        ch(2, 2),             // unread but BEHIND the furthest-read position
        ch(3, 3, read: true),
        ch(4, 4),             // unread, ahead
        ch(5, 5),             // unread, ahead
      ];
      expect(desiredChapterIds(c, OfflineKeepRule.nUnread, 2), {4, 5});
    },
  );

  test('nUnread unions pinned even when read or beyond N', () {
    final c = [...chapters, ch(1, 1, read: true, pinned: true)];
    // id 1 already present but pinned; plus next-2-unread {3,4}
    expect(desiredChapterIds(c, OfflineKeepRule.nUnread, 2), {1, 3, 4});
  });

  test(
    'nUnread skips a permanently-errored chapter and lets the next unread '
    'chapter take its slot, instead of wasting the slot forever',
    () {
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
    },
  );

  test(
    'nUnread still lets a pinned errored chapter through — pinning is '
    'sticky regardless of device state',
    () {
      final c = [
        ch(1, 1, read: true),
        ch(3, 3, deviceState: OfflineDeviceState.error, pinned: true),
        ch(4, 4),
      ];
      expect(desiredChapterIds(c, OfflineKeepRule.nUnread, 1), {3, 4});
    },
  );
}
