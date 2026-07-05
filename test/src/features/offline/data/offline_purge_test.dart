import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  Future<Set<int>> ids() async =>
      (await db.libraryManga()).map((m) => m.id).toSet();

  test('purges phantoms (null/0 timestamp, no downloads), keeps real + '
      'downloaded', () async {
    // phantom: browsed, null timestamp, no chapters
    await db.upsertMangaMetadata(
        id: 1, title: 'phantom-null', updatedAt: DateTime(2026));
    // phantom: '0' sentinel timestamp (went through the fallback reconstruction)
    await db.upsertMangaMetadata(
        id: 2, title: 'phantom-zero', updatedAt: DateTime(2026), inLibraryAt: '0');
    // real library manga: proper timestamp
    await db.upsertMangaMetadata(
        id: 3, title: 'real', updatedAt: DateTime(2026), inLibraryAt: '1700000000');
    // null timestamp BUT has a downloaded chapter -> protected
    await db.upsertMangaMetadata(
        id: 4, title: 'downloaded', updatedAt: DateTime(2026));
    await db.upsertChapterMetadata(
        id: 40, mangaId: 4, name: 'c', chapterIndex: 1, isRead: false,
        lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
        pageCount: 1, updatedAt: DateTime(2026));
    await db.setChapterDeviceState(40, OfflineDeviceState.downloaded, bytes: 1);

    final removed = await db.purgeNonLibraryManga();

    expect(removed, 2);
    expect(await ids(), {3, 4});
  });
}
