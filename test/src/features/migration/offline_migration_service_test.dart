// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/migration/data/offline_migration_service.dart';
import 'package:tsumiru/src/features/migration/domain/migration_models.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store.dart';
import 'package:tsumiru/src/features/offline/data/offline_sync.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

import '../../../helpers/offline_test_db.dart';

/// Records transfer calls; returns fixed pages, or throws for the failure case.
class FakePageStore implements OfflinePageStore {
  final List<({int fromM, int fromC, int toM, int toC, bool keepSource})> calls =
      [];
  Set<int> failFromChapters = {};

  @override
  Future<List<({int pageIndex, String relPath, int bytes})>> transferChapter(
    int fromMangaId,
    int fromChapterId,
    int toMangaId,
    int toChapterId, {
    required bool keepSource,
  }) async {
    calls.add((
      fromM: fromMangaId,
      fromC: fromChapterId,
      toM: toMangaId,
      toC: toChapterId,
      keepSource: keepSource
    ));
    if (failFromChapters.contains(fromChapterId)) {
      throw const OfflineTransferException('boom');
    }
    return [
      (pageIndex: 0, relPath: '$toMangaId/$toChapterId/000.jpg', bytes: 50),
      (pageIndex: 1, relPath: '$toMangaId/$toChapterId/001.jpg', bytes: 50),
    ];
  }

  @override
  Future<void> deleteChapter(int mangaId, int chapterId) async {}
  @override
  Future<int> chapterBytes(int mangaId, int chapterId) async => 0;
  @override
  Future<({String relPath, int bytes})> writePage(
          int m, int c, int i, List<int> b, String e) async =>
      (relPath: '', bytes: 0);
  @override
  Future<void> clearAll() async {}
}

MangaDto mangaDto(int id) => Fragment$MangaDto(
      id: id,
      title: 'M$id',
      bookmarkCount: 0,
      chapters: Fragment$MangaDto$chapters(totalCount: 0),
      downloadCount: 0,
      genre: const [],
      inLibrary: true,
      inLibraryAt: '0',
      initialized: true,
      meta: const [],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords:
          Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
      unreadCount: 0,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/$id',
    );

ChapterDto chapterDto(int id, int mangaId, double number) => Fragment$ChapterDto(
      id: id,
      mangaId: mangaId,
      name: 'c$number',
      chapterNumber: number,
      sourceOrder: id,
      isRead: false,
      isBookmarked: false,
      isDownloaded: false,
      lastPageRead: 0,
      pageCount: 2,
      fetchedAt: '0',
      uploadDate: '0',
      lastReadAt: '0',
      url: '',
      meta: const <Fragment$ChapterDto$meta>[],
    );

void main() {
  late OfflineDatabase db;
  late FakePageStore store;
  late List<int> reconciled;

  setUp(() {
    db = testOfflineDatabase();
    store = FakePageStore();
    reconciled = [];
  });
  tearDown(() => db.close());

  // Source manga 1 has chapter 101 (number N) downloaded; target manga 2 has
  // chapter 201 (same number N). fetchChapters returns the source/target lists.
  Future<OfflineMigrationService> seed({
    OfflineKeepRule sourceRule = OfflineKeepRule.off,
    double sourceNumber = 1,
    double targetNumber = 1,
    bool targetAlreadyDownloaded = false,
  }) async {
    await db.upsertMangaMetadata(
        id: 1, title: 'M1', updatedAt: DateTime(2026));
    if (sourceRule != OfflineKeepRule.off) {
      await db.setKeepRule(1, sourceRule, 4);
    }
    await db.upsertChapterMetadata(
      id: 101, mangaId: 1, name: 'a', chapterIndex: 0, isRead: false,
      lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
      pageCount: 2, updatedAt: DateTime(2026),
    );
    await db.setChapterDeviceState(101, OfflineDeviceState.downloaded,
        bytes: 100);
    if (targetAlreadyDownloaded) {
      await db.upsertChapterMetadata(
        id: 201, mangaId: 2, name: 'a', chapterIndex: 0, isRead: false,
        lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
        pageCount: 2, updatedAt: DateTime(2026),
      );
      await db.setChapterDeviceState(201, OfflineDeviceState.downloaded,
          bytes: 100);
    }
    return OfflineMigrationService(
      db: db,
      pageStore: store,
      sync: OfflineSync(db),
      fetchManga: (id) async => mangaDto(id),
      fetchChapters: (id) async => id == 1
          ? [chapterDto(101, 1, sourceNumber)]
          : [chapterDto(201, 2, targetNumber)],
      reconcileTarget: (id) async => reconciled.add(id),
    );
  }

  const migrate = MigrationOption(migrateDownloads: true, deleteSource: true);
  const copy = MigrationOption(migrateDownloads: true, deleteSource: false);

  test('Migrate moves the matched download onto the target and clears source',
      () async {
    final svc = await seed();
    final res = await svc.migrate(fromMangaId: 1, toMangaId: 2, options: migrate);
    expect(res.movedDownloads, 1);
    expect(store.calls.single.keepSource, isFalse); // moved, not copied
    final target = (await db.chapterById(201))!;
    expect(target.deviceState, OfflineDeviceState.downloaded);
    expect(target.pinned, isTrue); // pinned so reconcile can't evict the move
    final source = (await db.chapterById(101))!;
    expect(source.deviceState, OfflineDeviceState.none); // cleared
    expect(reconciled, [2]); // target reconciled once
  });

  test('Copy duplicates files and leaves the source download intact', () async {
    final svc = await seed();
    final res = await svc.migrate(fromMangaId: 1, toMangaId: 2, options: copy);
    expect(res.movedDownloads, 1);
    expect(store.calls.single.keepSource, isTrue); // copied
    expect((await db.chapterById(201))!.deviceState,
        OfflineDeviceState.downloaded);
    expect((await db.chapterById(101))!.deviceState,
        OfflineDeviceState.downloaded); // source kept
  });

  test('a transfer failure pins the target for a reconcile re-fetch', () async {
    final svc = await seed();
    store.failFromChapters = {101};
    final res = await svc.migrate(fromMangaId: 1, toMangaId: 2, options: migrate);
    expect(res.refetchedDownloads, 1);
    expect(res.movedDownloads, 0);
    final target = (await db.chapterById(201))!;
    expect(target.pinned, isTrue); // pinned → reconcile will server-download it
    expect(target.deviceState, isNot(OfflineDeviceState.downloaded));
  });

  test('an unmatched source download is neither moved nor refetched', () async {
    final svc = await seed(sourceNumber: 1, targetNumber: 9);
    final res = await svc.migrate(fromMangaId: 1, toMangaId: 2, options: migrate);
    expect(res.movedDownloads, 0);
    expect(res.refetchedDownloads, 0);
    expect(res.unmatchedDownloads, 1);
    expect(store.calls, isEmpty);
  });

  test('does not clobber a chapter the target already has downloaded', () async {
    final svc = await seed(targetAlreadyDownloaded: true);
    final res = await svc.migrate(fromMangaId: 1, toMangaId: 2, options: migrate);
    expect(res.movedDownloads, 0);
    expect(store.calls, isEmpty); // skipped
  });

  test('keep-rule is copied to the target', () async {
    final svc = await seed(sourceRule: OfflineKeepRule.all);
    await svc.migrate(
      fromMangaId: 1,
      toMangaId: 2,
      options: const MigrationOption(
          migrateOfflineSettings: true,
          migrateDownloads: false,
          deleteSource: true),
    );
    expect((await db.mangaById(2))!.keepRule, OfflineKeepRule.all);
    expect((await db.mangaById(2))!.keepUnreadCount, 4);
  });

  test('Migrate resets the source keep-rule and unpins it for the purge',
      () async {
    final svc = await seed(sourceRule: OfflineKeepRule.all);
    // An extra pinned source chapter with no target match — it must be unpinned
    // so the post-removal reconcile can evict it (closes the lingering gap).
    await db.upsertChapterMetadata(
      id: 102, mangaId: 1, name: 'b', chapterIndex: 1, isRead: false,
      lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
      pageCount: 2, updatedAt: DateTime(2026),
    );
    await db.setChapterDeviceState(102, OfflineDeviceState.downloaded);
    await db.setChapterPinned(102, true);
    await svc.migrate(fromMangaId: 1, toMangaId: 2, options: migrate);
    expect((await db.mangaById(1))!.keepRule, OfflineKeepRule.off);
    expect((await db.chapterById(102))!.pinned, isFalse);
  });

  test('nothing to do when both offline toggles are off', () async {
    final svc = await seed();
    final res = await svc.migrate(
      fromMangaId: 1,
      toMangaId: 2,
      options: const MigrationOption(
          migrateOfflineSettings: false, migrateDownloads: false),
    );
    expect(res.movedDownloads, 0);
    expect(store.calls, isEmpty);
    expect(reconciled, isEmpty);
  });
}
