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

  test('maps defaults, last read and an unmirrored rating', () async {
    await db.upsertMangaMetadata(
      id: 7,
      title: 'Solo',
      thumbnailUrl: '/t.jpg',
      updatedAt: DateTime(2026),
    );
    final m = await db.mangaById(7);
    final dto = offlineMangaToDto(m!, chapterCount: 12);
    expect(dto.id, 7);
    expect(dto.title, 'Solo');
    expect(dto.thumbnailUrl, '/t.jpg');
    expect(dto.user.inLibrary, true);
    expect(dto.user.unreadCount, 0);
    expect(dto.user.downloadCount, 0);
    expect(dto.chapters.totalCount, 12);

    expect(
      offlineMangaToDto(
        m,
        lastReadAt: '1700000000000',
      ).user.lastReadChapter?.user.lastReadAt,
      '1700000000000',
    );
    expect(offlineMangaToDto(m).user.lastReadChapter, isNull);

    // A null warning (pre-rating row) must not resolve to SAFE, or an
    // adult-tagged series leaks past the offline content filter.
    await db.upsertMangaMetadata(
      id: 77,
      title: 'Untagged Rating',
      updatedAt: DateTime(2026, 1, 1),
      sourceId: 'src-002',
      sourceName: 'Legacy Source',
      genre: jsonEncode(['Hentai']),
    );
    final unrated = offlineMangaToDto((await db.mangaById(77))!);
    expect(unrated.source?.contentWarning, Enum$ContentWarning.MIXED);
    expect(isAdultManga(unrated.source?.contentWarning, unrated.genre), true);
  });
}
