import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_dto_mappers.dart';
import 'package:tsumiru/src/features/offline/data/offline_runtime_storage.dart';
import 'package:tsumiru/src/features/offline/data/offline_sync.dart';

import '../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  late ProviderContainer container;
  late OfflineRuntimeStorage runtime;
  late MangaDto manga;

  setUp(() async {
    db = testOfflineDatabase();
    container = ProviderContainer();
    runtime = container.read(offlineRuntimeStorageProvider.notifier);
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
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  for (final writer in ['manga', 'chapters', 'prune', 'categories']) {
    test(
      '$writer keeps runtime drain pending through its final async write',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        final sync = OfflineSync(
          db,
          taskTracker: runtime.track,
          onSynced: () async {
            started.complete();
            await release.future;
          },
        );
        final chapter = offlineChapterToDto((await db.chapterById(1))!);
        final work = switch (writer) {
          'manga' => sync.syncManga(manga, fetchedAtGen: db.syncGeneration),
          'chapters' => sync.syncChapters([chapter]),
          'prune' => sync.pruneRemovedLibraryManga([manga]),
          _ => sync.syncCategories([offlineDefaultCategoryDto(1)]),
        };
        await started.future;
        var drained = false;
        final drain = runtime.drain().then((_) => drained = true);
        await Future<void>.delayed(Duration.zero);
        expect(drained, isFalse);
        release.complete();
        await work;
        await drain;
        expect(drained, isTrue);
      },
    );
  }

  test(
    'stale admission cannot alter manga, chapters, categories or library membership',
    () async {
      var notifications = 0;
      final sync = OfflineSync(
        db,
        taskTracker: runtime.track,
        isCurrentSession: () => false,
        onSynced: () async {
          notifications++;
        },
      );
      await sync.syncManga(
        manga.copyWith(title: 'Wrong account'),
        fetchedAtGen: 0,
      );
      expect(
        await sync.syncChapters([
          offlineChapterToDto(
            (await db.chapterById(1))!,
          ).copyWith(name: 'Wrong account', isRead: true),
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

  test(
    'switch during settling refetch drains A without mirroring its late result',
    () async {
      await db.upsertCategory(9, 'Retained', 0, isHidden: false);
      await db.replaceMangaCategories(1, [9]);
      await db.setChapterReadState(1, true);
      final generation = db.syncGeneration;
      await db.clearReadStateDirtyIfUnchanged(1, isRead: true);
      final started = Completer<void>();
      final response = Completer<MangaDto?>();
      var current = true;
      var fetches = 0;
      var notifications = 0;
      final sync = OfflineSync(
        db,
        taskTracker: runtime.track,
        isCurrentSession: () => current,
        refetchManga: (_) {
          fetches++;
          started.complete();
          return response.future;
        },
        onSynced: () async {
          notifications++;
        },
      );
      final work = sync.syncManga(manga, fetchedAtGen: generation);
      await started.future;
      current = false;
      var drained = false;
      final drain = runtime.drain().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      response.complete(manga.copyWith(title: 'Late result'));
      await work;
      await drain;
      expect((await db.mangaById(1))!.title, 'Original');
      expect((await db.categoriesForManga(1)).map((category) => category.id), [
        9,
      ]);
      expect(fetches, 1);
      expect(notifications, 0);
    },
  );
}
