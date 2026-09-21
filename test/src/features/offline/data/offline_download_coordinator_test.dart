// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/offline/data/chapter_commit.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_coordinator.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_manager.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/reconcile_types.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';

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
    Future<void> Function()? onPermissionDenied,
    Future<void> Function()? onResolve,
    bool Function()? isCurrentSession,
    bool Function()? requiresAuth,
    int parallelPageLimit = 5,
  }) {
    final engine = ChapterDownloadEngine(
      writePage: store,
      parallelPageLimit: parallelPageLimit,
      maxAttempts: 2,
      backoff: (_) => Duration.zero,
      refreshAuth: () async => refreshOk,
      fetchPage: (url) async {
        if (onFetch != null) await onFetch();
        if (pageOffline) throw const PageOfflineException('test-offline');
        if (auth401 || (requiresAuth?.call() ?? false)) {
          throw const PageAuthException();
        }
        if (fail) throw Exception('boom');
        return (bytes: [1, 2, 3], ext: 'jpg');
      },
    );
    return OfflineDownloadCoordinator(
      db: db,
      engine: engine,
      store: store,
      resolvePages: (_) async {
        await onResolve?.call();
        if (resolveThrows != null) throw resolveThrows;
        return pages;
      },
      persistedPaused: persistedPaused,
      onServerUnreachable: onServerUnreachable,
      onPermissionDenied: onPermissionDenied,
      isCurrentSession: isCurrentSession,
    );
  }

  for (final deleted in [true, false]) {
    test(
      deleted
          ? 'late permission denial ignores a replaced generation'
          : 'late permission denial ignores an old session',
      () async {
        await seedChapter(1, 7, 3);
        final resolving = Completer<void>();
        final release = Completer<void>();
        var current = true;
        var pauses = 0;
        final coordinator = coord(
          isCurrentSession: () => current,
          onResolve: () async {
            resolving.complete();
            await release.future;
          },
          resolveThrows: const AccountPermissionDenied(
            Enum$UserPermission.DOWNLOAD_CHAPTERS,
          ),
          onPermissionDenied: () async {
            pauses++;
          },
        );
        await coordinator.queueChapter(1);
        final before = (await db.chapterById(1))!;
        final running = coordinator.enqueueChapter(before);
        await resolving.future;
        if (deleted) {
          await coordinator.beginDelete(1, timeout: Duration.zero);
          await db.bumpChapterGeneration(1);
          await db.setChapterDeviceState(1, OfflineDeviceState.none);
          coordinator.endDelete(1);
          await coordinator.queueChapter(1);
        } else {
          current = false;
        }
        release.complete();
        await running;
        expect(pauses, 0);
        final after = (await db.chapterById(1))!;
        expect(
          after.deviceState,
          deleted ? OfflineDeviceState.queued : OfflineDeviceState.downloading,
        );
        expect(
          after.downloadGeneration,
          before.downloadGeneration + (deleted ? 1 : 0),
        );
      },
    );
  }

  test(
    'permission denial pauses the queue and keeps completed chapters',
    () async {
      await seedChapter(1, 7, 3);
      await seedChapter(2, 7, 3);
      await seedChapter(3, 7, 3);
      await db.setChapterDeviceState(
        3,
        OfflineDeviceState.downloaded,
        bytes: 99,
      );
      var denied = 0;
      final coordinator = coord(
        resolveThrows: const AccountPermissionDenied(
          Enum$UserPermission.DOWNLOAD_CHAPTERS,
        ),
        onPermissionDenied: () async {
          denied++;
        },
      );
      await coordinator.queueChapter(1);
      await coordinator.queueChapter(2);
      await coordinator.pumpDownloads();
      expect(denied, 1);
      expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.error);
      expect((await db.chapterById(2))!.deviceState, OfflineDeviceState.queued);
      expect(
        (await db.chapterById(3))!.deviceState,
        OfflineDeviceState.downloaded,
      );
      expect((await db.chapterById(3))!.bytes, 99);
    },
  );

  test(
    'unverified permission parks without terminal errors or denial',
    () async {
      await seedChapter(1, 7, 3);
      var denied = 0;
      final coordinator = coord(
        resolveThrows: const AccountPermissionUnavailable(),
        onPermissionDenied: () async {
          denied++;
        },
      );
      await coordinator.queueChapter(1);
      await coordinator.pumpDownloads();
      expect(denied, 0);
      expect(
        (await db.chapterById(1))!.deviceState,
        OfflineDeviceState.downloading,
      );
    },
  );

  for (final error in <Object>[
    OperationException(
      graphqlErrors: const [GraphQLError(message: 'Unauthorized')],
    ),
    OperationException(
      linkException: HttpLinkServerException(
        response: http.Response('{"errors":[]}', 401),
        parsedResponse: const Response(response: {}, errors: []),
      ),
    ),
  ]) {
    test(
      'page-list authentication failure remains resumable: ${error.runtimeType}',
      () async {
        await seedChapter(1, 7, 3);
        var reject = true;
        var denials = 0;
        final coordinator = coord(
          onResolve: () async {
            if (reject) {
              throw OperationMessageException(error as OperationException);
            }
          },
          onPermissionDenied: () async {
            denials++;
          },
        );
        await coordinator.queueChapter(1);
        await coordinator.pumpDownloads();
        expect(
          (await db.chapterById(1))!.deviceState,
          OfflineDeviceState.downloading,
        );
        expect(denials, 0);
        reject = false;
        await coordinator.pumpDownloads();
        expect(
          (await db.chapterById(1))!.deviceState,
          OfflineDeviceState.downloaded,
        );
      },
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

  test('drain refuses a paused transfer that has not unwound', () async {
    await seedChapter(1, 7, 1);
    final started = Completer<void>();
    final release = Completer<void>();
    final coordinator = coord(
      pages: ['/p/0'],
      onFetch: () async {
        started.complete();
        await release.future;
      },
    );
    final transfer = coordinator.enqueueChapter((await db.chapterById(1))!);
    await started.future;
    coordinator.pause();
    await expectLater(
      coordinator.awaitIdle(timeout: Duration.zero),
      throwsStateError,
    );
    release.complete();
    await transfer;
    await coordinator.awaitIdle(timeout: Duration.zero);
  });

  test('refused pause-and-drain restores the previous pause state', () async {
    await seedChapter(1, 7, 1);
    final started = Completer<void>();
    final release = Completer<void>();
    final coordinator = coord(
      pages: ['/p/0'],
      onFetch: () async {
        started.complete();
        await release.future;
      },
    );
    final transfer = coordinator.enqueueChapter((await db.chapterById(1))!);
    await started.future;
    await expectLater(
      coordinator.pauseAndDrain(timeout: Duration.zero),
      throwsStateError,
    );
    expect(coordinator.isPaused, isFalse);
    coordinator.pause();
    await expectLater(
      coordinator.pauseAndDrain(timeout: Duration.zero),
      throwsStateError,
    );
    expect(coordinator.isPaused, isTrue);
    release.complete();
    await transfer;
  });

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
      expect(store.pages.keys.toSet(), {
        '1/0',
        '1/1',
        '1/2',
      }, reason: 'every page re-fetched against the fresh list');
    },
  );

  test('staging with an unreadable manifest is wiped, never adopted', () async {
    await seedChapter(1, 7, 3);
    // Page files survived but the manifest didn't (torn on the crash that
    // ended the last run). Nothing identifies which download they belong to,
    // so they must not be counted as already-downloaded.
    store.staged[1] = {0: 99, 1: 99};

    await coord().enqueueChapter((await db.chapterById(1))!);

    expect(store.pages.keys.toSet(), {
      '1/0',
      '1/1',
      '1/2',
    }, reason: 'every page re-fetched rather than trusting orphaned files');
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

  test(
    'persisted pause during a page stops later pages and resumes after restoration',
    () async {
      await seedChapter(1, 7, 3);
      final fetching = Completer<void>();
      final release = Completer<void>();
      var paused = false;
      var fetched = 0;
      final coordinator = coord(
        parallelPageLimit: 1,
        persistedPaused: () => paused,
        onFetch: () async {
          fetched++;
          if (fetched == 1) {
            fetching.complete();
            await release.future;
          }
        },
      );
      await coordinator.queueChapter(1);
      final running = coordinator.pumpDownloads();
      await fetching.future;
      paused = true;
      release.complete();
      await running;
      expect(fetched, 1);
      expect(
        (await db.chapterById(1))!.deviceState,
        OfflineDeviceState.downloading,
      );
      paused = false;
      await coordinator.pumpDownloads();
      expect(
        (await db.chapterById(1))!.deviceState,
        OfflineDeviceState.downloaded,
      );
    },
  );

  for (final other in [
    const PageOfflineException('HTTP 502'),
    const PageAuthException(),
  ]) {
    test('parallel permission denial wins over ${other.runtimeType}', () async {
      await seedChapter(1, 7, 2);
      final bothFetching = Completer<void>();
      var fetching = 0;
      var denied = 0;
      final coordinator = OfflineDownloadCoordinator(
        db: db,
        store: store,
        engine: ChapterDownloadEngine(
          writePage: store,
          fetchPage: (url) async {
            fetching++;
            if (fetching == 2) bothFetching.complete();
            await bothFetching.future;
            if (url == '/denied') {
              throw const AccountPermissionDenied(
                Enum$UserPermission.DOWNLOAD_CHAPTERS,
              );
            }
            throw other;
          },
          refreshAuth: () async => false,
        ),
        resolvePages: (_) async => ['/denied', '/other'],
        onPermissionDenied: () async {
          denied++;
        },
      );
      await coordinator.queueChapter(1);
      await coordinator.pumpDownloads();
      expect(denied, 1);
      expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.error);
      expect(store.committed, isEmpty);
    });
  }

  test('failed auth refresh holds until credentials are restored', () async {
    await seedChapter(1, 7, 3);
    var needsAuth = true;
    final coordinator = coord(requiresAuth: () => needsAuth);
    await coordinator.queueChapter(1);
    await coordinator.pumpDownloads();
    expect(
      (await db.chapterById(1))!.deviceState,
      OfflineDeviceState.downloading,
    );
    needsAuth = false;
    await coordinator.pumpDownloads();
    expect(
      (await db.chapterById(1))!.deviceState,
      OfflineDeviceState.downloaded,
    );
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

  for (final chapterLock in [false, true]) {
    for (final changed in ['pin', 'rule', 'generation']) {
      test(
        'stale eviction preserves $changed change while waiting for ${chapterLock ? 'chapter lock' : 'ownership'}',
        () async {
          await db.upsertMangaMetadata(
            id: 7,
            title: 'M',
            updatedAt: DateTime(2026),
          );
          await db.setKeepRule(7, OfflineKeepRule.off, 3);
          await seedChapter(9, 7, 1);
          await db.setChapterDeviceState(
            9,
            OfflineDeviceState.downloaded,
            bytes: 10,
          );
          store.seedCommitted(9, {0: 10});
          final waiting = Completer<void>();
          final release = Completer<void>();
          Future<void>? heldLock;
          if (chapterLock) {
            final locked = Completer<void>();
            heldLock = ChapterFileLock.run(9, () async {
              locked.complete();
              await release.future;
            });
            await locked.future;
          }
          var checks = 0;
          final removed = <int>[];
          final running = reconcileMangaCore(
            db: db,
            repo: OfflineRepository(db: db, paths: OfflinePaths('/tmp/x')),
            manager: OfflineDownloadManager(
              db: db,
              store: store,
              fetchPageUrls: (_) async => [],
              fetchBytes: (_) async => (bytes: [1], ext: 'jpg'),
            ),
            coordinator: coord(),
            nets: SafetyNetConfig.off,
            mangaId: 7,
            verifyPermission: () async {
              if (chapterLock && ++checks == 2) waiting.complete();
            },
            withOwnership: chapterLock
                ? null
                : (action) async {
                    waiting.complete();
                    await release.future;
                    await action();
                  },
            removeFromWorker: (id, gen) async => removed.add(id),
          );
          await waiting.future;
          await pumpEventQueue();
          switch (changed) {
            case 'pin':
              await db.setChapterPinned(9, true);
            case 'rule':
              await db.setKeepRule(7, OfflineKeepRule.all, 3);
            case 'generation':
              await db.bumpChapterGeneration(9);
          }
          final before = (await db.chapterById(9))!;
          release.complete();
          await running;
          await heldLock;
          final after = (await db.chapterById(9))!;
          expect(after.downloadGeneration, before.downloadGeneration);
          expect(after.deviceState, OfflineDeviceState.downloaded);
          expect(store.committed[9], {0: 10});
          expect(removed, isEmpty);
        },
      );
    }
  }

  for (final chapterLock in [false, true]) {
    test(
      chapterLock
          ? 'permission lost while waiting for chapter lock preserves files'
          : 'permission lost while waiting for eviction ownership preserves files and generation',
      () async {
        await db.upsertMangaMetadata(
          id: 7,
          title: 'M',
          updatedAt: DateTime(2026),
        );
        await db.setKeepRule(7, OfflineKeepRule.all, 3);
        await seedChapter(9, 7, 1);
        await db.setChapterDeviceState(
          9,
          OfflineDeviceState.orphaned,
          bytes: 10,
        );
        store.seedCommitted(9, {0: 10});
        await db.upsertChapterMetadata(
          id: 10,
          mangaId: 7,
          name: 'pending',
          chapterIndex: 2,
          isRead: false,
          lastPageRead: 0,
          isBookmarked: false,
          serverIsDownloaded: false,
          pageCount: 1,
          updatedAt: DateTime(2026),
        );
        final waiting = Completer<void>();
        final release = Completer<void>();
        Future<void>? heldLock;
        if (chapterLock) {
          final locked = Completer<void>();
          heldLock = ChapterFileLock.run(9, () async {
            locked.complete();
            await release.future;
          });
          await locked.future;
        }
        var allowed = true;
        var permissionChecks = 0;
        final enqueued = <int>[];
        final before = (await db.chapterById(9))!;
        final running = reconcileMangaCore(
          db: db,
          repo: OfflineRepository(db: db, paths: OfflinePaths('/tmp/x')),
          manager: OfflineDownloadManager(
            db: db,
            store: store,
            fetchPageUrls: (_) async => [],
            fetchBytes: (_) async => (bytes: [1], ext: 'jpg'),
          ),
          coordinator: coord(),
          nets: SafetyNetConfig.off,
          mangaId: 7,
          verifyPermission: () async {
            permissionChecks++;
            if (chapterLock && permissionChecks == 2) waiting.complete();
            if (!allowed) {
              throw const AccountPermissionDenied(
                Enum$UserPermission.DOWNLOAD_CHAPTERS,
              );
            }
          },
          withOwnership: chapterLock
              ? null
              : (action) async {
                  waiting.complete();
                  await release.future;
                  await action();
                },
          enqueueServerDownload: (ids) async => enqueued.addAll(ids),
        );
        final expectation = expectLater(
          running,
          throwsA(isA<AccountPermissionDenied>()),
        );
        await waiting.future;
        allowed = false;
        release.complete();
        await expectation;
        await heldLock;
        final after = (await db.chapterById(9))!;
        expect(after.downloadGeneration, before.downloadGeneration);
        expect(after.deviceState, before.deviceState);
        expect(store.committed[9], {0: 10});
        expect(enqueued, isEmpty);
      },
    );
  }
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

      expect(removed, [
        9,
      ], reason: 'the Android worker must be told to cancel before eviction');
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
