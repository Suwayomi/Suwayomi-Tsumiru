// test/src/features/offline/data/offline_read_fallback_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_read_fallback.dart';
import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  Future<Never> boom() async => throw Exception('server unreachable');

  test('library: returns server result when fetch succeeds', () async {
    final r = await libraryWithOfflineFallback(
        fetch: () async => null, db: db, offlineEnabled: true);
    expect(r, isNull); // server returned null -> passed through, no fallback
  });

  test('library: falls back to catalog when fetch throws', () async {
    await db.upsertMangaMetadata(id: 1, title: 'A', updatedAt: DateTime(2026));
    await db.upsertMangaMetadata(id: 2, title: 'B', updatedAt: DateTime(2026));
    final r = await libraryWithOfflineFallback(
        fetch: boom, db: db, offlineEnabled: true);
    expect(r!.map((m) => m.id).toSet(), {1, 2});
  });

  test('library: rethrows when offline disabled', () async {
    await db.upsertMangaMetadata(id: 1, title: 'A', updatedAt: DateTime(2026));
    expect(libraryWithOfflineFallback(fetch: boom, db: db, offlineEnabled: false),
        throwsException);
  });

  test('library: rethrows when catalog empty', () async {
    expect(libraryWithOfflineFallback(fetch: boom, db: db, offlineEnabled: true),
        throwsException);
  });

  test('manga: falls back to the catalog row on throw', () async {
    await db.upsertMangaMetadata(id: 5, title: 'M', updatedAt: DateTime(2026));
    final r = await mangaWithOfflineFallback(
        fetch: boom, db: db, offlineEnabled: true, mangaId: 5);
    expect(r!.id, 5);
  });

  test('manga: rethrows when the manga is not in the catalog', () async {
    expect(
        mangaWithOfflineFallback(
            fetch: boom, db: db, offlineEnabled: true, mangaId: 404),
        throwsException);
  });

  test('chapters: falls back to catalog chapters on throw', () async {
    await db.upsertChapterMetadata(id: 10, mangaId: 5, name: 'c10',
        chapterIndex: 1, isRead: false, lastPageRead: 0, isBookmarked: false,
        serverIsDownloaded: true, pageCount: 1, updatedAt: DateTime(2026));
    final r = await chaptersWithOfflineFallback(
        fetch: boom, db: db, offlineEnabled: true, mangaId: 5);
    expect(r!.single.id, 10);
  });
}
