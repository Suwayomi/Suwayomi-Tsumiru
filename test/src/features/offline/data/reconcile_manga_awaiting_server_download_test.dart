// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Regression guard: a manga-details-triggered reconcile (reconcileManga /
// reconcileMangaWidget / reconcileMangaContainer) that has to ask the server
// to download a chapter first must register the manga in
// awaitingServerDownloads, exactly like the automatic keep-rule catch-up
// pass already did. Without this, the progressive
// pull-as-soon-as-the-server-queue-drains mechanism
// (offline_chapter_catchup.dart's downloadsMapProvider listener) never fires
// for a manga-details-triggered download, which instead sits waiting for the
// next full-library sync.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/data/downloads/downloads_repository.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/features/offline/data/offline_awaiting_server_downloads.dart';
import 'package:tsumiru/src/features/offline/data/offline_background_downloads.dart';
import 'package:tsumiru/src/features/offline/data/offline_chapter_catchup.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_coordinator.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_manager.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../../helpers/fake_page_store.dart';
import '../../../../helpers/offline_test_db.dart';

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

/// Records every enqueue call; throws instead when [shouldFail] is set, to
/// exercise the "only register on success" branch.
class _SpyDownloadsRepository extends DownloadsRepository {
  _SpyDownloadsRepository() : super(_dummyClient(), _dummyClient());

  final List<int> enqueued = [];
  bool shouldFail = false;

  @override
  Future<void> addChaptersBatchToDownloadQueue(List<int> chapterIds) async {
    if (shouldFail) throw Exception('enqueue failed');
    enqueued.addAll(chapterIds);
  }
}

void main() {
  late OfflineDatabase db;
  final store = FakePageStore();
  late _SpyDownloadsRepository downloadsRepo;

  setUp(() {
    OfflineDownloadCoordinator.resetSharedStateForTest();
    resetChapterCatchUpStateForTest();
    db = testOfflineDatabase();
    downloadsRepo = _SpyDownloadsRepository();
  });
  tearDown(() {
    resetChapterCatchUpStateForTest();
    db.close();
  });

  Future<void> seedMangaNeedingServerDownload(int mangaId) async {
    await db.upsertMangaMetadata(
      id: mangaId,
      title: 'M$mangaId',
      updatedAt: DateTime(2026),
    );
    await db.setKeepRule(mangaId, OfflineKeepRule.all, 3);
    // Wanted by the rule, but the server hasn't fetched it from the source yet
    // -- exactly the condition that makes the reconciler call
    // enqueueServerDownload instead of queueing a device download directly.
    await db.upsertChapterMetadata(
      id: mangaId * 100 + 1,
      mangaId: mangaId,
      name: 'c1',
      chapterIndex: 1,
      isRead: false,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: false,
      pageCount: 1,
      updatedAt: DateTime(2026),
    );
  }

  Future<WidgetRef> harness(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          offlineEnabledProvider.overrideWithValue(true),
          offlineActiveProvider.overrideWithValue(true),
          offlineDatabaseProvider.overrideWithValue(db),
          offlinePathsProvider.overrideWithValue(const OfflinePaths('/tmp/x')),
          offlinePageStoreProvider.overrideWithValue(store),
          downloadsRepositoryProvider.overrideWithValue(downloadsRepo),
          offlineDownloadCoordinatorProvider.overrideWithValue(
            OfflineDownloadCoordinator(
              db: db,
              engine: ChapterDownloadEngine(
                fetchPage: (_) async => throw UnimplementedError(),
                writePage: store,
                refreshAuth: () async => false,
              ),
              store: store,
              resolvePages: (_) async => const [],
            ),
          ),
          offlineDownloadManagerProvider.overrideWithValue(
            OfflineDownloadManager(
              db: db,
              store: store,
              fetchPageUrls: (_) async => const [],
              fetchBytes: (_) async => throw UnimplementedError(),
            ),
          ),
          downloadStarterProvider.overrideWithValue(
            ({bool userInitiated = false}) async {},
          ),
        ],
        child: Consumer(
          builder: (_, ref, __) {
            captured = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets(
    'reconcileMangaWidget registers the manga in awaitingServerDownloads '
    'on a successful server-download enqueue',
    (tester) async {
      await seedMangaNeedingServerDownload(1);
      final ref = await harness(tester);

      await reconcileMangaWidget(ref, 1);

      expect(downloadsRepo.enqueued, [101]);
      expect(awaitingServerDownloads, contains(1),
          reason: 'without this, the progressive pull-on-server-drain '
              'mechanism never learns manga 1 owes a device pull, and it '
              'would sit waiting for the next full-library sync instead');
    },
  );

  testWidgets(
    'reconcileMangaWidget does NOT register the manga when the enqueue fails',
    (tester) async {
      await seedMangaNeedingServerDownload(2);
      downloadsRepo.shouldFail = true;
      final ref = await harness(tester);

      await reconcileMangaWidget(ref, 2);

      expect(awaitingServerDownloads, isNot(contains(2)),
          reason: 'a failed enqueue produced no server queue activity, so '
              'no drain edge would ever retry it -- registering it anyway '
              'would leave a phantom obligation nothing can complete');
    },
  );

  test(
    'reconcileManga (Ref entry point) registers on success, same as the '
    'WidgetRef variant',
    () async {
      await seedMangaNeedingServerDownload(3);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineActiveProvider.overrideWithValue(true),
        offlineDatabaseProvider.overrideWithValue(db),
        offlinePathsProvider.overrideWithValue(const OfflinePaths('/tmp/x')),
        downloadsRepositoryProvider.overrideWithValue(downloadsRepo),
        offlineDownloadCoordinatorProvider.overrideWithValue(
          OfflineDownloadCoordinator(
            db: db,
            engine: ChapterDownloadEngine(
              fetchPage: (_) async => throw UnimplementedError(),
              writePage: store,
              refreshAuth: () async => false,
            ),
            store: store,
            resolvePages: (_) async => const [],
          ),
        ),
        offlineDownloadManagerProvider.overrideWithValue(
          OfflineDownloadManager(
            db: db,
            store: store,
            fetchPageUrls: (_) async => const [],
            fetchBytes: (_) async => throw UnimplementedError(),
          ),
        ),
      ]);
      addTearDown(container.dispose);
      // reconcileManga takes a plain Ref (a NotifierProvider/Provider
      // callback's ref), not a WidgetRef -- capture one via a throwaway
      // provider instead of trying to cast a WidgetRef to it.
      final ref = container.read(Provider<Ref>((ref) => ref));

      await reconcileManga(ref, 3);

      expect(awaitingServerDownloads, contains(3));
    },
  );

  test(
    'reconcileMangaContainer (ProviderContainer entry point) registers on '
    'success, same as the WidgetRef variant',
    () async {
      await seedMangaNeedingServerDownload(4);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineActiveProvider.overrideWithValue(true),
        offlineDatabaseProvider.overrideWithValue(db),
        offlinePathsProvider.overrideWithValue(const OfflinePaths('/tmp/x')),
        downloadsRepositoryProvider.overrideWithValue(downloadsRepo),
        offlineDownloadCoordinatorProvider.overrideWithValue(
          OfflineDownloadCoordinator(
            db: db,
            engine: ChapterDownloadEngine(
              fetchPage: (_) async => throw UnimplementedError(),
              writePage: store,
              refreshAuth: () async => false,
            ),
            store: store,
            resolvePages: (_) async => const [],
          ),
        ),
        offlineDownloadManagerProvider.overrideWithValue(
          OfflineDownloadManager(
            db: db,
            store: store,
            fetchPageUrls: (_) async => const [],
            fetchBytes: (_) async => throw UnimplementedError(),
          ),
        ),
      ]);
      addTearDown(container.dispose);

      await reconcileMangaContainer(container, 4);

      expect(awaitingServerDownloads, contains(4));
    },
  );
}
