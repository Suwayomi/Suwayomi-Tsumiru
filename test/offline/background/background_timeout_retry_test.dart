import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/background/background_completion_log.dart';
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
  late BackgroundCompletionLog log;

  setUp(() async {
    ChapterFileLock.resetForTest();
    OfflineDownloadCoordinator.resetSharedStateForTest();
    db = testOfflineDatabase();
    final tmp = await Directory.systemTemp.createTemp('timeout-retry-');
    store = IoOfflinePageStore(OfflinePaths(tmp.path));
    log = BackgroundCompletionLog(File('${tmp.path}/completion.jsonl'));
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

  test('removing a keep rule invalidates a delayed queue request', () async {
    await db.setChapterDeviceState(5, OfflineDeviceState.none);
    await db.setKeepRule(1, OfflineKeepRule.all, 3);
    final before = (await db.chapterById(5))!;
    await db.setKeepRule(1, OfflineKeepRule.off, 3);
    await coordinator().queueChapter(
      5,
      expectedGeneration: before.downloadGeneration,
      expectedKeepConfig: (rule: OfflineKeepRule.all, count: 3),
    );
    final after = (await db.chapterById(5))!;
    expect(after.deviceState, OfflineDeviceState.none);
    expect(after.downloadGeneration, before.downloadGeneration);
  });

  test('matching generation and keep rule admit the queue request', () async {
    await db.setChapterDeviceState(5, OfflineDeviceState.none);
    await db.setKeepRule(1, OfflineKeepRule.all, 3);
    final before = (await db.chapterById(5))!;
    await coordinator().queueChapter(
      5,
      expectedGeneration: before.downloadGeneration,
      expectedKeepConfig: (rule: OfflineKeepRule.all, count: 3),
    );
    final after = (await db.chapterById(5))!;
    expect(after.deviceState, OfflineDeviceState.queued);
    expect(after.downloadGeneration, before.downloadGeneration);
  });

  test('a stale explicit retry cannot restore a deleted chapter', () async {
    await db.setChapterDeviceState(5, OfflineDeviceState.error);
    final before = (await db.chapterById(5))!;
    await db.bumpChapterGeneration(5);
    await db.setChapterDeviceState(5, OfflineDeviceState.none);
    final controller = coordinator();
    await controller.queueChapter(
      5,
      allowErrored: true,
      expectedGeneration: before.downloadGeneration,
    );
    final deleted = (await db.chapterById(5))!;
    expect(deleted.deviceState, OfflineDeviceState.none);
    expect(deleted.downloadGeneration, before.downloadGeneration + 1);

    await db.setChapterDeviceState(5, OfflineDeviceState.error);
    await controller.queueChapter(
      5,
      allowErrored: true,
      expectedGeneration: deleted.downloadGeneration,
    );
    await controller.queueChapter(
      5,
      allowErrored: true,
      expectedGeneration: deleted.downloadGeneration,
    );
    final retried = (await db.chapterById(5))!;
    expect(retried.deviceState, OfflineDeviceState.queued);
    expect(retried.downloadGeneration, deleted.downloadGeneration + 1);
  });

  test(
    'timeout markers parse without producing chapter terminal records',
    () async {
      await log.appendTimeout();
      final entries = await log.parse();
      expect(entries.single, isA<TimeoutEntry>());
      expect(entries.whereType<ChapterEntry>(), isEmpty);
    },
  );

  test(
    'replay reports timeout before truncating and preserves chapter state',
    () async {
      final before = await db.chapterById(5);
      await log.appendTimeout();
      await log.appendTimeout();
      var notifications = 0;
      Future<void> replay() => replayCompletionLog(
        db: db,
        store: store,
        log: log,
        onTimeout: () async {
          notifications++;
          expect((await log.parse()).whereType<TimeoutEntry>().length, 2);
        },
      );
      await replay();
      expect(notifications, 1);
      expect(await db.chapterById(5), before);
      expect(await log.parse(), isEmpty);
      await replay();
      expect(notifications, 1);
    },
  );

  test(
    'automatic queueing leaves an error and its generation untouched',
    () async {
      await db.setChapterDeviceState(5, OfflineDeviceState.error);
      await db.bumpChapterGeneration(5);
      await coordinator().queueChapter(5);
      final row = (await db.chapterById(5))!;
      expect(row.deviceState, OfflineDeviceState.error);
      expect(row.downloadGeneration, 1);
    },
  );

  test(
    'explicit retry advances generation and survives replay of the old error',
    () async {
      await db.setChapterDeviceState(5, OfflineDeviceState.error);
      await db.bumpChapterGeneration(5);
      await log.appendChapter(
        chapterId: 5,
        status: 'error',
        pages: 0,
        bytes: 0,
        generation: 1,
      );
      final controller = coordinator();
      await controller.queueChapter(5, allowErrored: true);
      expect((await db.chapterById(5))!.downloadGeneration, 2);
      await controller.queueChapter(5, allowErrored: true);
      expect((await db.chapterById(5))!.downloadGeneration, 2);
      await replayCompletionLog(db: db, store: store, log: log);
      final row = (await db.chapterById(5))!;
      expect(row.downloadGeneration, 2);
      expect(row.deviceState, OfflineDeviceState.queued);
      expect(await log.parse(), isEmpty);
    },
  );
}
