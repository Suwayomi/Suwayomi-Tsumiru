// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/offline/data/chapter_commit.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_coordinator.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_manager.dart';
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
  });

  test(
    'a failed re-download preserves the chapter already on device',
    () async {
      await seedChapter(1, 7, 3);
      store.seedCommitted(1, {0: 10, 1: 10, 2: 10});
      await db.setChapterDeviceState(1, OfflineDeviceState.downloaded);
      final manager = OfflineDownloadManager(
        db: db,
        store: store,
        fetchPageUrls: (_) async => ['/a', '/b', '/c'],
        fetchBytes: (_) async => throw Exception('network died'),
      );

      await expectLater(
        manager.downloadChapter((await db.chapterById(1))!),
        throwsException,
      );

      expect(
        store.committed.containsKey(1),
        isTrue,
        reason: 'the previous copy survives a failed attempt',
      );
      expect(store.deletedChapters, isNot(contains(1)));
    },
  );

  test(
    'force downloads a chapter the server does not mark downloaded',
    () async {
      await db.upsertChapterMetadata(
        id: 9,
        mangaId: 7,
        name: 'c9',
        chapterIndex: 1,
        isRead: false,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: false,
        pageCount: 1,
        updatedAt: DateTime(2026),
      );
      final manager = OfflineDownloadManager(
        db: db,
        store: store,
        fetchPageUrls: (_) async => ['/p/0'],
        fetchBytes: (_) async => (bytes: [1], ext: 'jpg'),
      );

      await manager.downloadChapter((await db.chapterById(9))!, force: true);

      expect(
        (await db.chapterById(9))!.deviceState,
        OfflineDeviceState.downloaded,
      );
    },
  );
}
