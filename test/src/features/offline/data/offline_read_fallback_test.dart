// test/src/features/offline/data/offline_read_fallback_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_read_fallback.dart';
import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  // A genuine loss of connectivity — the only case that should fall back.
  Future<Never> boom() async => throw const SocketException('unreachable');

  // The offline library only lists series with files on this device, so most
  // seeds need at least one downloaded chapter to be visible at all.
  var seededChapterId = 900;
  Future<void> seedDownloadedChapter(
    int mangaId, {
    bool isRead = true,
    String? lastReadAt,
  }) async {
    final id = seededChapterId++;
    await db.upsertChapterMetadata(
      id: id,
      mangaId: mangaId,
      name: 'dl$id',
      chapterIndex: 90 + id,
      isRead: isRead,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: true,
      pageCount: 1,
      updatedAt: DateTime(2026),
      lastReadAt: lastReadAt,
    );
    await db.setChapterDeviceState(id, OfflineDeviceState.downloaded, bytes: 1);
  }

  // The server answered with an error — must surface, never be masked.
  Future<Never> serverError() async => throw Exception('HTTP 500');

  test(
    'library: falls back to the downloaded catalog when fetch throws',
    () async {
      await db.upsertCategory(1, 'Reading', 0, isHidden: false);
      await db.upsertCategory(2, 'Plan to read', 1, isHidden: false);
      await db.upsertMangaMetadata(
        id: 1,
        title: 'A',
        updatedAt: DateTime(2026),
      );
      await db.upsertMangaMetadata(
        id: 2,
        title: 'B',
        updatedAt: DateTime(2026),
      );
      // A third, uncategorized manga: must come back with an empty list, not
      // crash or silently borrow manga 1's/2's categories.
      await db.upsertMangaMetadata(
        id: 3,
        title: 'C',
        updatedAt: DateTime(2026),
      );
      // In the catalog but nothing downloaded: not part of the offline library
      // (people go offline to read, not to browse metadata).
      await db.upsertMangaMetadata(
        id: 5,
        title: 'E',
        updatedAt: DateTime(2026),
      );
      await db.replaceMangaCategories(1, [1, 2]);
      await db.replaceMangaCategories(2, [1]);
      await seedDownloadedChapter(1);
      await seedDownloadedChapter(2);
      await seedDownloadedChapter(3);

      // ch1 read+downloaded, ch2 unread+downloaded, ch3 unread+downloaded.
      // The continue button points at ch2 (earliest unread on the device).
      await db.upsertMangaMetadata(
        id: 4,
        title: 'D',
        updatedAt: DateTime(2026),
      );
      for (final (id, idx, read) in [
        (11, 1, true),
        (12, 2, false),
        (13, 3, false),
      ]) {
        await db.upsertChapterMetadata(
          id: id,
          mangaId: 4,
          name: 'c$id',
          chapterIndex: idx,
          isRead: read,
          lastPageRead: 0,
          isBookmarked: false,
          serverIsDownloaded: true,
          pageCount: 1,
          updatedAt: DateTime(2026),
        );
        await db.setChapterDeviceState(id, OfflineDeviceState.downloaded);
      }

      final r = await libraryWithOfflineFallback(
        fetch: boom,
        db: db,
        offlineEnabled: true,
      );
      final byId = {for (final m in r!) m.id: m};
      expect(byId.keys.toSet(), {1, 2, 3, 4});
      expect(byId[1]!.categories.nodes.map((n) => n.id).toList(), [1, 2]);
      expect(byId[2]!.categories.nodes.map((n) => n.id).toList(), [1]);
      expect(byId[3]!.categories.nodes, isEmpty);
      expect(byId[4]!.user.firstUnreadChapter?.id, 12);
    },
  );

  test('library: rethrows a server error rather than masking it with the '
      'catalog', () async {
    await db.upsertMangaMetadata(id: 1, title: 'A', updatedAt: DateTime(2026));
    expect(
      libraryWithOfflineFallback(
        fetch: serverError,
        db: db,
        offlineEnabled: true,
      ),
      throwsA(predicate((e) => e.toString().contains('HTTP 500'))),
    );
  });
}
