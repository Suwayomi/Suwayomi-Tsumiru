import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_dto_mappers.dart';
import 'package:tsumiru/src/features/offline/data/offline_sync.dart';

import '../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  late MangaDto manga;

  setUp(() async {
    db = testOfflineDatabase();
    await db.upsertMangaMetadata(
      id: 1,
      title: 'Original',
      updatedAt: DateTime(2026),
      inLibraryAt: '1',
      unreadCount: 1,
    );
    await db.upsertChapterMetadata(
      id: 1,
      mangaId: 1,
      name: 'Original chapter',
      chapterIndex: 1,
      isRead: false,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: false,
      pageCount: 1,
      updatedAt: DateTime(2026),
    );
    manga = offlineMangaToDto((await db.mangaById(1))!);
  });
  tearDown(() => db.close());

  test(
    'stale admission cannot alter manga, chapters, categories or library membership',
    () async {
      var notifications = 0;
      final sync = OfflineSync(
        db,
        isCurrentSession: () => false,
        onSynced: () async {
          notifications++;
        },
      );
      await sync.syncManga(
        manga.copyWith(title: 'Wrong account'),
        fetchedAtGen: 0,
      );
      final stray = offlineChapterToDto((await db.chapterById(1))!);
      expect(
        await sync.syncChapters([
          stray.copyWith(
            name: 'Wrong account',
            user: stray.user.copyWith(isRead: true),
          ),
        ]),
        isEmpty,
      );
      await sync.pruneRemovedLibraryManga([manga.copyWith(id: 2)]);
      await sync.syncCategories([offlineDefaultCategoryDto(1)]);
      expect((await db.mangaById(1))!.title, 'Original');
      expect((await db.mangaById(1))!.inLibraryAt, '1');
      expect((await db.chapterById(1))!.name, 'Original chapter');
      expect((await db.chapterById(1))!.isRead, isFalse);
      expect(await db.allOfflineCategories(), isEmpty);
      expect(notifications, 0);
    },
  );
}
