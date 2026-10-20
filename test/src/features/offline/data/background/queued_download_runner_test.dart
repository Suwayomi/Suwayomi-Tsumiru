// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/offline/data/background/background_completion_log.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/background/queued_download_runner.dart';
import 'package:tsumiru/src/features/offline/data/chapter_manifest.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

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
  late bool serverDownloaded;
  late Future<bool> Function(int) enqueue;
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
        for (final chapter in queue)
          serverChapter(
            chapter.chapterId,
          ).copyWith(serverIsDownloaded: serverDownloaded),
      ],
      enqueueServer: enqueue,
      download: (row, chapter) async {
        expect(row.id, chapter.chapterId);
        downloads.add(chapter.chapterId);
        return attempt(chapter);
      },
      shouldStop: (_) async => stopped,
      capBlocked: () async => capReached,
      persist: (value) async {
        ledger = value;
      },
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
    serverDownloaded = true;
    enqueue = (_) async => throw StateError('Already downloaded');
    attempt = stage;
  });

  test(
    'permission denial is terminal without spending retries on later wakes',
    () async {
      attempt = (_) async => throw const AccountPermissionDenied(
        Enum$UserPermission.DOWNLOAD_CHAPTERS,
      );
      final result = await run();
      expect(result.interrupted, isTrue);
      expect(ledger.queuedDownloadRetries, isEmpty);
      expect(ledger.queuedServerRetries, isEmpty);
      expect(
        (await log.parse()).whereType<ChapterEntry>().single.status,
        'permissionDenied',
      );
      attempt = stage;
      await run();
      expect(downloads, [1]);
    },
  );

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
}
