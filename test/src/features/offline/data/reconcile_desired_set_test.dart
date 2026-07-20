import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/reconcile_logic.dart';

OfflineChapter ch(int id, int idx, {bool read = false, bool pinned = false}) =>
    OfflineChapter(
      id: id, mangaId: 1, name: 'c$id', chapterIndex: idx, isRead: read,
      lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
      deviceState: OfflineDeviceState.none, pageCount: 1, bytes: 0,
      pinned: pinned, downloadedAt: null, progressDirty: false,
      bookmarkDirty: false, readStateDirty: false, updatedAt: DateTime(2026),
      downloadGeneration: 0,
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

  test('nUnread keeps the N lowest-index unread', () {
    expect(desiredChapterIds(chapters, OfflineKeepRule.nUnread, 2), {3, 4});
  });

  test('nUnread unions pinned even when read or beyond N', () {
    final c = [...chapters, ch(1, 1, read: true, pinned: true)];
    // id 1 already present but pinned; plus next-2-unread {3,4}
    expect(desiredChapterIds(c, OfflineKeepRule.nUnread, 2), {1, 3, 4});
  });
}
