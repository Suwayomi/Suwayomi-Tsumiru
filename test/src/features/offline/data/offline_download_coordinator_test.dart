// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/chapter_commit.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_coordinator.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_manager.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/reconcile_types.dart';

import '../../../../helpers/fake_page_store.dart';
import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  late FakePageStore store;
  setUp(() {
    ChapterFileLock.resetForTest();
    OfflineDownloadCoordinator.resetSharedStateForTest();
    db = testOfflineDatabase();
    store = FakePageStore();
  });
  tearDown(() => db.close());

  Future<void> seedChapter(int id, int mangaId, int pageCount) =>
      db.upsertChapterMetadata(
        id: id,
        mangaId: mangaId,
        name: 'c$id',
        chapterIndex: 1,
        isRead: false,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: pageCount,
        updatedAt: DateTime(2026),
      );

  /// Build a coordinator whose engine fetches with the given behaviour.
  OfflineDownloadCoordinator coord({
    List<String> pages = const ['/p/0', '/p/1', '/p/2'],
    bool fail = false,
    bool auth401 = false,
    bool refreshOk = false,
    bool Function()? persistedPaused,
    Future<void> Function()? onFetch,
    Future<int> Function(int, int)? measureOverride,
    bool pageOffline = false,
    Object? resolveThrows,
    void Function()? onServerUnreachable,
  }) {
    final engine = ChapterDownloadEngine(
      writePage: store,
      maxAttempts: 2,
      backoff: (_) => Duration.zero,
      refreshAuth: () async => refreshOk,
      fetchPage: (url) async {
        if (onFetch != null) await onFetch();
        if (pageOffline) throw const PageOfflineException('test-offline');
        if (auth401) throw const PageAuthException();
        if (fail) throw Exception('boom');
        return (bytes: [1, 2, 3], ext: 'jpg');
      },
    );
    return OfflineDownloadCoordinator(
      db: db,
      engine: engine,
      store: store,
      resolvePages: (_) async {
        if (resolveThrows != null) throw resolveThrows;
        return pages;
      },
      persistedPaused: persistedPaused,
      onServerUnreachable: onServerUnreachable,
    );
  }

  test(
    'downloads every page, stores rows, marks downloaded with bytes',
    () async {
      await seedChapter(1, 7, 3);
      await coord().enqueueChapter((await db.chapterById(1))!);
      final c = await db.chapterById(1);
      expect(c!.deviceState, OfflineDeviceState.downloaded);
      expect(await db.downloadedPageCount(1), 3);
      expect(c.bytes, 9); // 3 pages x 3 bytes
    },
  );

  test('no resolved pages -> error', () async {
    await seedChapter(1, 7, 3);
    await coord(pages: const []).enqueueChapter((await db.chapterById(1))!);
    expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.error);
  });

  test('resume only fetches pages not already staged', () async {
    await seedChapter(1, 7, 3);
    // A previous run got page 0 down before it was killed.
    store.seedStaged(1, {0: 3}, indices: [0, 1, 2]);
    await coord().enqueueChapter((await db.chapterById(1))!);
    expect(
      (await db.chapterById(1))!.deviceState,
      OfflineDeviceState.downloaded,
    );
    expect(store.pages.keys.toSet(), {'1/1', '1/2'}); // only the 2 missing
  });

  test(
    'staging from a stale page list is restarted, not merged into',
    () async {
      await seedChapter(1, 7, 3);
      // Staging left by a run whose chapter had a different page count; mixing
      // the two would commit a chapter assembled from both.
      store.seedStaged(1, {0: 3, 1: 3}, indices: [0, 1]);
      await coord().enqueueChapter((await db.chapterById(1))!);
      expect(
        (await db.chapterById(1))!.deviceState,
        OfflineDeviceState.downloaded,
      );
      expect(
        store.pages.keys.toSet(),
        {'1/0', '1/1', '1/2'},
        reason: 'every page re-fetched against the fresh list',
      );
    },
  );

  test('staging with an unreadable manifest is wiped, never adopted', () async {
    await seedChapter(1, 7, 3);
    // Page files survived but the manifest didn't (torn on the crash that
    // ended the last run). Nothing identifies which download they belong to,
    // so they must not be counted as already-downloaded.
    store.staged[1] = {0: 99, 1: 99};

    await coord().enqueueChapter((await db.chapterById(1))!);

    expect(
      store.pages.keys.toSet(),
      {'1/0', '1/1', '1/2'},
      reason: 'every page re-fetched rather than trusting orphaned files',
    );
    expect(
      (await db.chapterById(1))!.deviceState,
      OfflineDeviceState.downloaded,
    );
    expect(
      store.committed[1]!.values,
      everyElement(3),
      reason: 'committed bytes are this run\'s pages, not the orphans',
    );
  });

  test('a chapter left incomplete publishes nothing', () async {
    await seedChapter(1, 7, 3);
    // Cancelled once the download is under way, so pages are missing when the
    // engine unwinds. The chapter must be absent, not a short one.
    late OfflineDownloadCoordinator c;
    c = coord(onFetch: () async => c.cancel(1));
    await c.enqueueChapter((await db.chapterById(1))!);

    expect(
      (await db.chapterById(1))!.deviceState,
      isNot(OfflineDeviceState.downloaded),
    );
    expect(await db.downloadedPageCount(1), 0);
    expect(store.committed, isEmpty, reason: 'nothing was published');
    expect(
      store.manifests.containsKey(1),
      isTrue,
      reason: 'staging survives for the resume',
    );
  });

  test('auth failure (401 + refresh dead) -> error', () async {
    await seedChapter(1, 7, 3);
    await coord(
      auth401: true,
      refreshOk: false,
    ).enqueueChapter((await db.chapterById(1))!);
    expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.error);
  });

  test('transient fetch failure exhausts retries -> error', () async {
    await seedChapter(1, 7, 3);
    await coord(fail: true).enqueueChapter((await db.chapterById(1))!);
    expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.error);
  });

  test('queueChapter marks queued without downloading', () async {
    await seedChapter(1, 7, 3);
    await coord().queueChapter(1);
    expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.queued);
    expect(store.pages, isEmpty);
  });

  test('pump drains the queue one chapter at a time', () async {
    await seedChapter(1, 7, 2);
    await seedChapter(2, 7, 2);
    final c = coord(pages: const ['/p/0', '/p/1']);
    await c.queueChapter(1);
    await c.queueChapter(2);
    await c.pumpDownloads();
    expect(
      (await db.chapterById(1))!.deviceState,
      OfflineDeviceState.downloaded,
    );
    expect(
      (await db.chapterById(2))!.deviceState,
      OfflineDeviceState.downloaded,
    );
  });

  test('pump resumes a chapter stranded as downloading', () async {
    await seedChapter(1, 7, 2);
    await db.setChapterDeviceState(1, OfflineDeviceState.downloading);
    await coord(pages: const ['/p/0', '/p/1']).pumpDownloads();
    expect(
      (await db.chapterById(1))!.deviceState,
      OfflineDeviceState.downloaded,
    );
  });

  test('paused pump does not download queued chapters', () async {
    await seedChapter(1, 7, 2);
    final c = coord(pages: const ['/p/0', '/p/1']);
    await c.queueChapter(1);
    c.pause();
    await c.pumpDownloads();
    expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.queued);
    expect(store.pages, isEmpty);
  });

  test(
    'paused enqueueChapter is a no-op (no re-start of a stranded chapter)',
    () async {
      await seedChapter(1, 7, 2);
      await db.setChapterDeviceState(1, OfflineDeviceState.downloading);
      final c = coord(pages: const ['/p/0', '/p/1']);
      c.pause();
      await c.enqueueChapter((await db.chapterById(1))!);
      // Left as-is (resumable), nothing written.
      expect(
        (await db.chapterById(1))!.deviceState,
        OfflineDeviceState.downloading,
      );
      expect(store.pages, isEmpty);
    },
  );

  test('resume after pause drains the queue', () async {
    await seedChapter(1, 7, 2);
    final c = coord(pages: const ['/p/0', '/p/1']);
    await c.queueChapter(1);
    c.pause();
    await c.pumpDownloads(); // gated — no-op
    expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.queued);
    await c.resume();
    expect(
      (await db.chapterById(1))!.deviceState,
      OfflineDeviceState.downloaded,
    );
  });

  test(
    'a chapter claimed by beginDelete is not (re)started by the pump',
    () async {
      await seedChapter(1, 7, 2);
      // Stranded downloading, as an in-flight delete leaves it after cancelling.
      await db.setChapterDeviceState(1, OfflineDeviceState.downloading);
      final c = coord(pages: const ['/p/0', '/p/1']);
      await c.beginDelete(1); // not active → returns immediately
      await c.pumpDownloads();
      // Must not resurrect it while the delete is in progress.
      expect(
        (await db.chapterById(1))!.deviceState,
        OfflineDeviceState.downloading,
      );
      expect(store.pages, isEmpty);
      // Once the delete releases it, normal draining resumes.
      c.endDelete(1);
      await c.pumpDownloads();
      expect(
        (await db.chapterById(1))!.deviceState,
        OfflineDeviceState.downloaded,
      );
    },
  );

  test(
    'reconcile eviction cancels the worker before deleting the copy',
    () async {
      // An orphaned (server-gone) chapter is always evicted. The eviction must
      // cancel the active downloader first, or an in-flight download re-writes the
      // whole chapter after the purge.
      await db.upsertMangaMetadata(
        id: 7,
        title: 'M',
        updatedAt: DateTime(2026),
      );
      await seedChapter(9, 7, 1);
      await db.setChapterDeviceState(9, OfflineDeviceState.orphaned, bytes: 10);

      final manager = OfflineDownloadManager(
        db: db,
        store: store,
        fetchPageUrls: (_) async => ['u'],
        fetchBytes: (_) async => (bytes: [1], ext: 'jpg'),
      );
      final removed = <int>[];
      await reconcileMangaCore(
        db: db,
        repo: OfflineRepository(db: db, paths: OfflinePaths('/tmp/x')),
        manager: manager,
        coordinator: coord(),
        nets: SafetyNetConfig.off,
        mangaId: 7,
        removeFromWorker: (id, gen) async => removed.add(id),
      );

      expect(
        removed,
        [9],
        reason: 'the Android worker must be told to cancel before eviction',
      );
      expect(
        (await db.chapterById(9))!.deviceState,
        OfflineDeviceState.none,
        reason: 'the orphaned copy is removed',
      );
    },
  );

  test(
    'a delete on a new coordinator blocks the old instance from resurrecting',
    () async {
      // The keep-alive provider can rebuild mid-drain: an old coordinator lingers
      // while deletes route through the replacement. The delete claim must be
      // visible across instances, or the old pump re-marks the chapter.
      await seedChapter(1, 7, 2);
      final oldCoord = coord(pages: const ['/p/0', '/p/1']);
      final newCoord = coord(pages: const ['/p/0', '/p/1']);

      await newCoord.beginDelete(1); // delete claimed on the replacement
      await db.setChapterDeviceState(
        1,
        OfflineDeviceState.none,
      ); // delete commits

      // The stale instance tries to (re)start the chapter it never knew was gone.
      await oldCoord.enqueueChapter((await db.chapterById(1))!);

      expect(
        (await db.chapterById(1))!.deviceState,
        OfflineDeviceState.none,
        reason: 'the cross-instance delete claim must block the old pump',
      );
      newCoord.endDelete(1);
    },
  );

  test(
    'overlapping deletes: the claim holds until the last one ends',
    () async {
      await seedChapter(1, 7, 2);
      await db.setChapterDeviceState(1, OfflineDeviceState.none); // deleted
      final c = coord(pages: const ['/p/0', '/p/1']);

      // A user delete and a reconcile eviction both claim the same chapter.
      await c.beginDelete(1);
      await c.beginDelete(1);

      // The first finishes and releases — the second is still deleting.
      c.endDelete(1);
      await c.queueChapter(1); // must still be blocked
      expect(
        (await db.chapterById(1))!.deviceState,
        OfflineDeviceState.none,
        reason: 'a surviving delete claim must keep the chapter guarded',
      );

      c.endDelete(1); // last claimant — now the guard releases
    },
  );

  test(
    'queueChapter refuses a chapter being deleted (no resurrection)',
    () async {
      await seedChapter(1, 7, 2);
      await db.setChapterDeviceState(
        1,
        OfflineDeviceState.none,
      ); // just deleted
      final c = coord(pages: const ['/p/0', '/p/1']);
      await c.beginDelete(1); // delete in progress
      await c.queueChapter(1);
      expect(
        (await db.chapterById(1))!.deviceState,
        OfflineDeviceState.none,
        reason: 'a queue request during a delete must not re-queue it',
      );
      c.endDelete(1);
    },
  );

  test('enqueueChapter refuses a chapter being deleted', () async {
    await seedChapter(1, 7, 2);
    final c = coord(pages: const ['/p/0', '/p/1']);
    await c.beginDelete(1);
    await c.enqueueChapter((await db.chapterById(1))!);
    expect(store.pages, isEmpty);
    expect(
      (await db.chapterById(1))!.deviceState,
      isNot(OfflineDeviceState.downloaded),
    );
  });

  test(
    'deleting the queued head does not stall the rest of the backlog',
    () async {
      await seedChapter(1, 7, 2); // queue head, being deleted
      await seedChapter(2, 8, 2); // must still download
      final c = coord(pages: const ['/p/0', '/p/1']);
      await c.queueChapter(1);
      await c.queueChapter(2);
      await c.beginDelete(1);
      await c.pumpDownloads();
      expect(
        (await db.chapterById(2))!.deviceState,
        OfflineDeviceState.downloaded,
      );
      c.endDelete(1);
    },
  );

  test('a delete landing before the commit is not overwritten by it', () async {
    await seedChapter(1, 7, 2);
    // The user deletes the chapter while its last pages are downloading. The
    // commit re-reads the row and must refuse rather than republish it.
    final c = coord(
      pages: const ['/p/0', '/p/1'],
      onFetch: () async => db.setChapterDeviceState(1, OfflineDeviceState.none),
    );
    await c.enqueueChapter((await db.chapterById(1))!);

    expect(
      (await db.chapterById(1))!.deviceState,
      OfflineDeviceState.none,
      reason: 'the delete wins — the completion does not resurrect it',
    );
    expect(await db.downloadedPageCount(1), 0);
    expect(store.committed, isEmpty);
  });

  test('a generation bumped mid-download refuses the commit', () async {
    await seedChapter(1, 7, 2);
    // A delete-then-requeue while the download ran: the pages in staging belong
    // to a generation nobody is waiting for.
    final c = coord(
      pages: const ['/p/0', '/p/1'],
      onFetch: () async => db.bumpChapterGeneration(1),
    );
    await c.enqueueChapter((await db.chapterById(1))!);

    expect(
      (await db.chapterById(1))!.deviceState,
      isNot(OfflineDeviceState.downloaded),
    );
    expect(store.committed, isEmpty);
    expect(
      store.manifests.containsKey(1),
      isFalse,
      reason: 'refused staging is dropped, not left to accumulate',
    );
  });

  test(
    'a delete committing mid-download is not overwritten by a late error',
    () async {
      await seedChapter(1, 7, 2);
      // The fetch fails, but a delete commits deviceState=none first (beginDelete
      // timed out and the engine kept running). The late error must not resurrect.
      final c = coord(
        fail: true,
        onFetch: () => db.setChapterDeviceState(1, OfflineDeviceState.none),
      );
      await c.enqueueChapter((await db.chapterById(1))!);

      expect(
        (await db.chapterById(1))!.deviceState,
        OfflineDeviceState.none,
        reason: 'the delete wins — a late error write is dropped',
      );
    },
  );

  test(
    'persisted pause flag gates the pump even on a fresh coordinator',
    () async {
      await seedChapter(1, 7, 2);
      var paused = true; // simulates the saved flag after a restart
      final c = coord(
        pages: const ['/p/0', '/p/1'],
        persistedPaused: () => paused,
      );
      await c.queueChapter(1);
      await c.pumpDownloads();
      expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.queued);
      paused = false; // user resumes
      await c.pumpDownloads();
      expect(
        (await db.chapterById(1))!.deviceState,
        OfflineDeviceState.downloaded,
      );
    },
  );

  group('parking on a dead network reports it', () {
    // Parking the pump is only half a plan: the reconnect that restarts it is
    // driven by the server-unreachable flag going up and back down. A park that
    // stays quiet strands the whole queue until the app restarts, with nothing
    // on screen saying why. Both park paths must raise it.

    test(
      'a page fetch that goes offline reports the server unreachable',
      () async {
        await seedChapter(1, 7, 3);
        var reported = false;
        await coord(
          pageOffline: true,
          onServerUnreachable: () => reported = true,
        ).enqueueChapter((await db.chapterById(1))!);

        expect(
          reported,
          isTrue,
          reason: 'without this the reconnect listener never fires',
        );
        expect(
          (await db.chapterById(1))!.deviceState,
          OfflineDeviceState.downloading,
          reason: 'left resumable, not errored',
        );
      },
    );

    test('a page-list resolve that goes offline reports it too', () async {
      await seedChapter(1, 7, 3);
      var reported = false;
      await coord(
        resolveThrows: const SocketException('no route to host'),
        onServerUnreachable: () => reported = true,
      ).enqueueChapter((await db.chapterById(1))!);

      expect(reported, isTrue);
      expect(
        (await db.chapterById(1))!.deviceState,
        OfflineDeviceState.downloading,
      );
    });

    test('a genuine page failure is an error, not a park', () async {
      await seedChapter(1, 7, 3);
      var reported = false;
      await coord(
        fail: true,
        onServerUnreachable: () => reported = true,
      ).enqueueChapter((await db.chapterById(1))!);

      expect(
        reported,
        isFalse,
        reason: 'a broken chapter is not an unreachable server',
      );
      expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.error);
    });
  });
}
