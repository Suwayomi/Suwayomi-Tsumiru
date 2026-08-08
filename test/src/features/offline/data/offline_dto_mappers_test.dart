import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/browse_center/domain/content_rating.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_dto_mappers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
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

  test('offlineMangaToDto carries firstUnreadChapter when supplied', () async {
    await db.upsertMangaMetadata(id: 7, title: 'Solo', updatedAt: DateTime(2026));
    final m = (await db.mangaById(7))!;
    await db.upsertChapterMetadata(id: 42, mangaId: 7, name: 'Ch 5',
        chapterIndex: 5, isRead: false, lastPageRead: 0, isBookmarked: false,
        serverIsDownloaded: true, pageCount: 18, updatedAt: DateTime(2026));
    final chapter = (await db.chaptersForManga(7)).single;

    final withTarget = offlineMangaToDto(m, firstUnread: chapter);
    expect(withTarget.firstUnreadChapter?.id, 42);
    expect(withTarget.firstUnreadChapter?.sourceOrder, 5);

    final noTarget = offlineMangaToDto(m);
    expect(noTarget.firstUnreadChapter, isNull);
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

  // A null warning (pre-rating row) must not resolve to SAFE, or an
  // adult-tagged series leaks past the offline content filter.
  test('an unmirrored rating defers to the tags, not to SAFE', () async {
    await db.upsertMangaMetadata(
      id: 77,
      title: 'Untagged Rating',
      updatedAt: DateTime(2026, 1, 1),
      sourceId: 'src-002',
      sourceName: 'Legacy Source',
      genre: jsonEncode(['Hentai']),
    );
    final dto = offlineMangaToDto((await db.mangaById(77))!);
    expect(dto.source?.contentWarning, Enum$ContentWarning.MIXED);
    expect(isAdultManga(dto.source?.contentWarning, dto.genre), true);
  });

  test('genre survives the JSON round-trip; junk degrades to no tags', () async {
    await db.upsertMangaMetadata(
      id: 78,
      title: 'Tagged',
      updatedAt: DateTime(2026, 1, 1),
      genre: jsonEncode(['Action', 'Drama']),
    );
    expect(offlineMangaToDto((await db.mangaById(78))!).genre,
        ['Action', 'Drama']);
    expect(offlineGenre('not json'), isEmpty);
    expect(offlineGenre('{"a":1}'), isEmpty);
    expect(offlineGenre(null), isEmpty);
  });

  test('full metadata survives upsert → read', () async {
    // Arrange – persist categories first (FK-free but order matters semantically)
    await db.upsertCategory(2, 'Action', 0, isHidden: false);
    await db.upsertCategory(5, 'Romance', 1, isHidden: false);

    // Persist a manga with all new fields
    await db.upsertMangaMetadata(
      id: 42,
      title: 'Test Manga',
      thumbnailUrl: 'https://example.com/thumb.jpg',
      updatedAt: DateTime(2026, 1, 1),
      sourceId: 'src-001',
      sourceName: 'Test Source',
      sourceLang: 'en',
      sourceContentWarning: 'SAFE',
      status: 'COMPLETED',
      unreadCount: 5,
      downloadCount: 2,
      bookmarkCount: 1,
      inLibraryAt: '1751234567000',
      latestFetchedAt: '1751111111000',
      latestUploadedAt: '1751222222000',
      totalChapters: 12,
    );

    // Persist category membership
    await db.replaceMangaCategories(42, [2, 5]);

    // Act – read back through the mapper
    final row = (await db.mangaById(42))!;
    final cats = await db.categoriesForManga(42);
    final dto = offlineMangaToDto(row, offlineCategories: cats);

    // Assert – every field round-trips
    expect(dto.id, 42);
    expect(dto.title, 'Test Manga');
    expect(dto.status, Enum$MangaStatus.COMPLETED);
    expect(dto.unreadCount, 5);
    expect(dto.downloadCount, 2);
    expect(dto.bookmarkCount, 1);
    expect(dto.inLibraryAt, '1751234567000');
    expect(dto.latestFetchedChapter?.fetchedAt, '1751111111000');
    expect(dto.latestUploadedChapter?.uploadDate, '1751222222000');
    expect(dto.chapters.totalCount, 12);
    final catIds = dto.categories.nodes.map((n) => n.id).toSet();
    expect(catIds, {2, 5});
  });

  test('unstored manga gets safe defaults + no categories', () async {
    await db.upsertMangaMetadata(
      id: 99,
      title: 'Minimal',
      updatedAt: DateTime(2026, 1, 1),
    );
    final row = (await db.mangaById(99))!;
    final cats = await db.categoriesForManga(99);
    final dto = offlineMangaToDto(row, offlineCategories: cats);

    expect(dto.status, Enum$MangaStatus.UNKNOWN);
    expect(dto.unreadCount, 0);
    expect(dto.downloadCount, 0);
    expect(dto.bookmarkCount, 0);
    expect(dto.categories.nodes, isEmpty);
  });

  test('allOfflineCategories returns persisted categories', () async {
    await db.upsertCategory(1, 'Shonen', 0, isHidden: false);
    await db.upsertCategory(2, 'Seinen', 1, isHidden: false);
    final all = await db.allOfflineCategories();
    expect(all.map((c) => c.id).toSet(), {1, 2});
  });
}
