// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/background/background_completion_log.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/background/queued_download_runner.dart';
import 'package:tsumiru/src/features/offline/data/chapter_manifest.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';

OfflineChapter serverChapter(int id) => OfflineChapter(
  id: id,
  mangaId: 1,
  name: 'Chapter $id',
  chapterIndex: id,
  isRead: false,
  lastPageRead: 0,
  isBookmarked: false,
  serverIsDownloaded: true,
  deviceState: OfflineDeviceState.queued,
  pageCount: 1,
  bytes: 0,
  updatedAt: DateTime(2026),
  pinned: false,
  progressDirty: false,
  bookmarkDirty: false,
  readStateDirty: false,
  readStateManual: false,
  syncedIsRead: false,
  downloadGeneration: 0,
  serverFetchAttempts: 0,
);

void main() {
  late IoOfflinePageStore store;
  late BackgroundCompletionLog log;
  late CatchupLedger ledger;
  late List<QueuedChapterSpec> queue;
  late List<int> downloads;
  late bool stopped;
  late bool capReached;
  late Future<QueuedAttempt> Function(QueuedChapterSpec) attempt;

  Future<QueuedAttempt> stage(QueuedChapterSpec chapter) async {
    await store.beginChapter(
      chapter.mangaId,
      chapter.chapterId,
      ChapterManifest(generation: chapter.generation, indices: [0]),
    );
    await store.writePage(chapter.mangaId, chapter.chapterId, 0, [1], 'jpg');
    return (bytes: 1, transient: false);
  }

  Future<QueuedRunResult> run() async {
    final result = await runQueuedDownloads(
      spec: CatchupWorkSpec(
        serverId: 'server',
        wifiOnly: false,
        storageCapEnabled: false,
        storageCapBytes: 0,
        manga: const [],
        queuedChapters: queue,
      ),
      ledger: ledger,
      store: store,
      log: log,
      fetchChapters: (_) async => [
        for (final chapter in queue) serverChapter(chapter.chapterId),
      ],
      enqueueServer: (_) async => throw StateError('Already downloaded'),
      download: (row, chapter) async {
        expect(row.id, chapter.chapterId);
        downloads.add(chapter.chapterId);
        return attempt(chapter);
      },
      shouldStop: (_) async => stopped,
      capBlocked: () async => capReached,
      persist: (value) async => ledger = value,
      allowance: 10,
    );
    ledger = result.ledger;
    return result;
  }

  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('tsumiru-queued-run-');
    store = IoOfflinePageStore(OfflinePaths(tmp.path));
    log = BackgroundCompletionLog(File('${tmp.path}/completion.jsonl'));
    ledger = const CatchupLedger();
    queue = [const QueuedChapterSpec(chapterId: 1, mangaId: 1, generation: 0)];
    downloads = [];
    stopped = false;
    capReached = false;
    attempt = stage;
  });

  test(
    'matching partial staging can finish above cap without admitting fresh work',
    () async {
      capReached = true;
      queue = [
        const QueuedChapterSpec(chapterId: 1, mangaId: 1, generation: 0),
        const QueuedChapterSpec(chapterId: 2, mangaId: 1, generation: 0),
      ];
      await store.beginChapter(
        1,
        1,
        const ChapterManifest(generation: 0, indices: [0, 1]),
      );
      await store.writePage(1, 1, 0, [1], 'jpg');
      attempt = (chapter) async {
        await store.writePage(chapter.mangaId, chapter.chapterId, 1, [
          2,
        ], 'jpg');
        return (bytes: 2, transient: false);
      };
      expect((await run()).completed, 1);
      expect(downloads, [1]);
      final success = (await log.parse()).whereType<ChapterEntry>().single;
      expect(success.chapterId, 1);
      expect(success.status, 'downloaded');
      expect(success.pages, 2);
      expect(await store.readManifest(1, 2), isNull);
    },
  );

  test('a fresh chapter above cap does not block later partial work', () async {
    capReached = true;
    queue = [
      const QueuedChapterSpec(chapterId: 1, mangaId: 1, generation: 0),
      const QueuedChapterSpec(chapterId: 2, mangaId: 1, generation: 0),
    ];
    await store.beginChapter(
      1,
      2,
      const ChapterManifest(generation: 0, indices: [0, 1]),
    );
    await store.writePage(1, 2, 0, [1], 'jpg');
    attempt = (chapter) async {
      await store.writePage(chapter.mangaId, chapter.chapterId, 1, [2], 'jpg');
      return (bytes: 2, transient: false);
    };
    expect((await run()).completed, 1);
    expect(downloads, [2]);
    expect(await store.readManifest(1, 1), isNull);
    final success = (await log.parse()).whereType<ChapterEntry>().single;
    expect(success.chapterId, 2);
    expect(success.status, 'downloaded');
    expect(success.pages, 2);
  });

  test('old-generation staging cannot admit a new request above cap', () async {
    capReached = true;
    queue = [const QueuedChapterSpec(chapterId: 1, mangaId: 1, generation: 1)];
    await store.beginChapter(
      1,
      1,
      const ChapterManifest(generation: 0, indices: [0, 1]),
    );
    await store.writePage(1, 1, 0, [1], 'jpg');
    expect((await run()).completed, 0);
    expect(downloads, isEmpty);
    expect(await log.parse(), isEmpty);
    expect((await store.readManifest(1, 1))!.generation, 0);
  });

  test(
    'thirty queued chapters finish across three ten-chapter wakes',
    () async {
      queue = List.generate(
        30,
        (index) =>
            QueuedChapterSpec(chapterId: index + 1, mangaId: 1, generation: 0),
      );
      for (var wake = 0; wake < 3; wake++) {
        expect((await run()).completed, 10);
      }
      expect(downloads, List.generate(30, (index) => index + 1));
      final successes = (await log.parse()).whereType<ChapterEntry>();
      expect(successes.length, 30);
      expect(successes.every((entry) => entry.status == 'downloaded'), isTrue);
    },
  );

  test(
    'complete staging repairs a missing success record without downloading',
    () async {
      await stage(queue.single);
      expect(await log.parse(), isEmpty);
      await run();
      expect(downloads, isEmpty);
      final success = (await log.parse()).whereType<ChapterEntry>().single;
      expect(success.status, 'downloaded');
      expect(success.generation, 0);
      expect(success.bytes, 1);
      expect(success.pages, 1);
    },
  );

  test(
    'a deletion and new generation allow the chapter to download again',
    () async {
      await run();
      await log.appendDeleted(1, 1);
      queue = [
        const QueuedChapterSpec(chapterId: 1, mangaId: 1, generation: 1),
      ];
      expect((await run()).completed, 1);
      expect(downloads, [1, 1]);
      final successes = (await log.parse()).whereType<ChapterEntry>().toList();
      expect(successes.map((entry) => entry.generation), [0, 1]);
      expect((await store.readManifest(1, 1))!.generation, 1);
    },
  );

  test(
    'five hard device failures produce one error and stop further attempts',
    () async {
      attempt = (_) async => (bytes: 0, transient: false);
      for (var wake = 0; wake < 7; wake++) {
        await run();
      }
      expect(downloads.length, 5);
      expect(ledger.queuedDownloadRetries, {'1:0': 5});
      final entries = (await log.parse()).whereType<ChapterEntry>().toList();
      expect(entries.length, 1);
      expect(entries.single.status, 'error');
    },
  );

  test(
    'spent server retries leave all five device attempts available',
    () async {
      ledger = const CatchupLedger(queuedServerRetries: {'1:0': 5});
      attempt = (_) async => (bytes: 0, transient: false);
      for (var wake = 0; wake < 6; wake++) {
        await run();
      }
      expect(downloads.length, 5);
      expect(ledger.queuedServerRetries, {'1:0': 5});
      expect(ledger.queuedDownloadRetries, {'1:0': 5});
      expect(
        (await log.parse()).whereType<ChapterEntry>().single.status,
        'error',
      );
    },
  );

  test('cancellation after the callback consumes no retry', () async {
    attempt = (_) async {
      stopped = true;
      return (bytes: 0, transient: false);
    };
    expect((await run()).interrupted, isTrue);
    expect(downloads, [1]);
    expect(ledger.queuedDownloadRetries, isEmpty);
    expect(ledger.queuedServerRetries, isEmpty);
    expect(await log.parse(), isEmpty);
  });

  test(
    'a transient failure stops the wake without consuming a retry',
    () async {
      queue = [
        const QueuedChapterSpec(chapterId: 1, mangaId: 1, generation: 0),
        const QueuedChapterSpec(chapterId: 2, mangaId: 1, generation: 0),
      ];
      attempt = (_) async => (bytes: 0, transient: true);
      expect((await run()).interrupted, isTrue);
      expect(downloads, [1]);
      expect(ledger.queuedDownloadRetries, isEmpty);
      expect(ledger.queuedServerRetries, isEmpty);
      expect(await log.parse(), isEmpty);
    },
  );
}
