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

  test('library: returns server result when fetch succeeds', () async {
    final r = await libraryWithOfflineFallback(
      fetch: () async => null,
      db: db,
      offlineEnabled: true,
    );
    expect(r, isNull); // server returned null -> passed through, no fallback
  });

  test('library: falls back to downloaded catalog series when fetch throws, '
      'and hides series with nothing on the device', () async {
    await db.upsertMangaMetadata(id: 1, title: 'A', updatedAt: DateTime(2026));
    await db.upsertMangaMetadata(id: 2, title: 'B', updatedAt: DateTime(2026));
    // In the catalog but nothing downloaded: not part of the offline library
    // (people go offline to read, not to browse metadata).
    await db.upsertMangaMetadata(id: 3, title: 'C', updatedAt: DateTime(2026));
    await seedDownloadedChapter(1);
    await seedDownloadedChapter(2);
    final r = await libraryWithOfflineFallback(
      fetch: boom,
      db: db,
      offlineEnabled: true,
    );
    expect(r!.map((m) => m.id).toSet(), {1, 2});
  });

  test('library: offline continue-reading target is the earliest unread '
      'downloaded chapter', () async {
    await db.upsertMangaMetadata(id: 1, title: 'A', updatedAt: DateTime(2026));
    // ch1 read+downloaded, ch2 unread+downloaded, ch3 unread+downloaded.
    // The button should point at ch2 (earliest unread that's on the device).
    for (final (id, idx, read) in [
      (11, 1, true),
      (12, 2, false),
      (13, 3, false),
    ]) {
      await db.upsertChapterMetadata(
        id: id,
        mangaId: 1,
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
    expect(r!.single.firstUnreadChapter?.id, 12);
  });

  test('library: no offline button when the next unread chapter is not '
      'downloaded', () async {
    await db.upsertMangaMetadata(id: 1, title: 'A', updatedAt: DateTime(2026));
    // Visible via one downloaded (read) chapter; the unread chapter exists
    // only as metadata (deviceState none), so it can't be opened offline ->
    // firstUnreadChapter stays null (button hidden), never a dead end.
    await seedDownloadedChapter(1, isRead: true);
    await db.upsertChapterMetadata(
      id: 21,
      mangaId: 1,
      name: 'c21',
      chapterIndex: 1,
      isRead: false,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: false,
      pageCount: 1,
      updatedAt: DateTime(2026),
    );
    final r = await libraryWithOfflineFallback(
      fetch: boom,
      db: db,
      offlineEnabled: true,
    );
    expect(r!.single.firstUnreadChapter, isNull);
  });

  test('library: rethrows when offline disabled', () async {
    await db.upsertMangaMetadata(id: 1, title: 'A', updatedAt: DateTime(2026));
    expect(
      libraryWithOfflineFallback(fetch: boom, db: db, offlineEnabled: false),
      throwsException,
    );
  });

  test('library: rethrows when catalog empty', () async {
    expect(
      libraryWithOfflineFallback(fetch: boom, db: db, offlineEnabled: true),
      throwsException,
    );
  });

  test('manga: falls back to the catalog row on throw', () async {
    await db.upsertMangaMetadata(id: 5, title: 'M', updatedAt: DateTime(2026));
    final r = await mangaWithOfflineFallback(
      fetch: boom,
      db: db,
      offlineEnabled: true,
      mangaId: 5,
    );
    expect(r!.id, 5);
  });

  test('manga: rethrows when the manga is not in the catalog', () async {
    expect(
      mangaWithOfflineFallback(
        fetch: boom,
        db: db,
        offlineEnabled: true,
        mangaId: 404,
      ),
      throwsException,
    );
  });

  test('chapters: falls back to catalog chapters on throw', () async {
    await db.upsertChapterMetadata(
      id: 10,
      mangaId: 5,
      name: 'c10',
      chapterIndex: 1,
      isRead: false,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: true,
      pageCount: 1,
      updatedAt: DateTime(2026),
    );
    final r = await chaptersWithOfflineFallback(
      fetch: boom,
      db: db,
      offlineEnabled: true,
      mangaId: 5,
    );
    expect(r!.single.id, 10);
  });

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

  test('reachability: reports reachable on a successful fetch', () async {
    final calls = <bool>[];
    await libraryWithOfflineFallback(
      fetch: () async => null,
      db: db,
      offlineEnabled: true,
      onReachability: calls.add,
    );
    expect(calls, [true]);
  });

  test('reachability: reports unreachable on a connection error, even while '
      'serving cache', () async {
    await db.upsertMangaMetadata(id: 1, title: 'A', updatedAt: DateTime(2026));
    await seedDownloadedChapter(1);
    final calls = <bool>[];
    await libraryWithOfflineFallback(
      fetch: boom,
      db: db,
      offlineEnabled: true,
      onReachability: calls.add,
    );
    expect(calls, [false]);
  });

  test(
    'reachability: reports unreachable on a connection error with no cache',
    () async {
      final calls = <bool>[];
      await expectLater(
        libraryWithOfflineFallback(
          fetch: boom,
          db: db,
          offlineEnabled: true,
          onReachability: calls.add,
        ),
        throwsException,
      );
      expect(calls, [false]);
    },
  );

  test(
    'reachability: reports reachable on a server error (server answered)',
    () async {
      await db.upsertMangaMetadata(
        id: 1,
        title: 'A',
        updatedAt: DateTime(2026),
      );
      final calls = <bool>[];
      await expectLater(
        libraryWithOfflineFallback(
          fetch: serverError,
          db: db,
          offlineEnabled: true,
          onReachability: calls.add,
        ),
        throwsA(predicate((e) => e.toString().contains('HTTP 500'))),
      );
      expect(calls, [true]);
    },
  );
}
