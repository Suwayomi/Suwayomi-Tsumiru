import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_dto_mappers.dart';
import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  test('offlineMangaToDto maps id/title/thumbnail and safe defaults', () async {
    await db.upsertMangaMetadata(id: 7, title: 'Solo', thumbnailUrl: '/t.jpg',
        updatedAt: DateTime(2026));
    final m = await db.mangaById(7);
    final dto = offlineMangaToDto(m!, chapterCount: 12);
    expect(dto.id, 7);
    expect(dto.title, 'Solo');
    expect(dto.thumbnailUrl, '/t.jpg');
    expect(dto.inLibrary, true);
    expect(dto.unreadCount, 0);
    expect(dto.downloadCount, 0);
    expect(dto.chapters.totalCount, 12);
  });

  test('mangaById returns null for an unknown id', () async {
    expect(await db.mangaById(999), isNull);
  });

  test('offlineMangaToDto carries lastReadAt for the "Last Read" sort',
      () async {
    await db.upsertMangaMetadata(id: 7, title: 'Solo', updatedAt: DateTime(2026));
    final m = (await db.mangaById(7))!;

    final withRead = offlineMangaToDto(m, lastReadAt: '1700000000000');
    expect(withRead.lastReadChapter?.lastReadAt, '1700000000000');

    final neverRead = offlineMangaToDto(m);
    expect(neverRead.lastReadChapter, isNull);
  });

  test('offlineChapterToDto maps fields from a catalog row', () async {
    await db.upsertChapterMetadata(id: 3, mangaId: 7, name: 'Ch 3',
        chapterIndex: 3, isRead: true, lastPageRead: 4, isBookmarked: false,
        serverIsDownloaded: true, pageCount: 20, updatedAt: DateTime(2026));
    final rows = await db.chaptersForManga(7);
    final dto = offlineChapterToDto(rows.single);
    expect(dto.id, 3);
    expect(dto.mangaId, 7);
    expect(dto.name, 'Ch 3');
    expect(dto.sourceOrder, 3);
    expect(dto.isRead, true);
    expect(dto.isDownloaded, true); // from serverIsDownloaded
    expect(dto.lastPageRead, 4);
    expect(dto.pageCount, 20);
  });
}
