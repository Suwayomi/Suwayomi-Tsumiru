import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/chapter_commit.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_coordinator.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';

import '../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  late IoOfflinePageStore store;

  setUp(() async {
    ChapterFileLock.resetForTest();
    OfflineDownloadCoordinator.resetSharedStateForTest();
    db = testOfflineDatabase();
    final tmp = await Directory.systemTemp.createTemp('timeout-retry-');
    store = IoOfflinePageStore(OfflinePaths(tmp.path));
    await db.upsertMangaMetadata(
      id: 1,
      title: 'Manga',
      updatedAt: DateTime(2026),
    );
    await db.upsertChapterMetadata(
      id: 5,
      mangaId: 1,
      name: 'Chapter',
      chapterIndex: 0,
      isRead: false,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: true,
      pageCount: 1,
      updatedAt: DateTime(2026),
    );
    await db.setChapterDeviceState(5, OfflineDeviceState.queued);
  });

  tearDown(() => db.close());

  OfflineDownloadCoordinator coordinator() => OfflineDownloadCoordinator(
    db: db,
    store: store,
    engine: ChapterDownloadEngine(
      writePage: store,
      refreshAuth: () async => false,
      fetchPage: (_) async => (bytes: [1], ext: 'jpg'),
    ),
    resolvePages: (_) async => ['/page/0'],
  );

  test('a delayed queue request cannot restore a deleted generation', () async {
    final before = (await db.chapterById(5))!;
    await db.bumpChapterGeneration(5);
    await db.setChapterDeviceState(5, OfflineDeviceState.none);
    await coordinator().queueChapter(
      5,
      expectedGeneration: before.downloadGeneration,
    );
    final after = (await db.chapterById(5))!;
    expect(after.deviceState, OfflineDeviceState.none);
    expect(after.downloadGeneration, before.downloadGeneration + 1);
  });
}
