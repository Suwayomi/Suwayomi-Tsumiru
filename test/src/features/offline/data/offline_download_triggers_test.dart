// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Regression guard for the bug where "Download all / unread" silently did
// nothing on Android: the trigger queued chapters but never started the
// download service. Every download trigger MUST go through
// downloadStarterProvider — these tests fail if one forgets to.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/features/offline/data/offline_background_downloads.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_coordinator.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_manager.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../../helpers/fake_page_store.dart';
import '../../../../helpers/offline_test_db.dart';

class _MangaRepository extends MangaBookRepository {
  _MangaRepository({this.requested, this.response})
    : super(
        GraphQLClient(
          link: Link.function((request, [forward]) => const Stream.empty()),
          cache: GraphQLCache(),
        ),
      );

  final Completer<void>? requested;
  final Completer<void>? response;

  @override
  Future<ChapterDto?> getChapter({required int chapterId}) async {
    expect(chapterId, 1);
    requested?.complete();
    await response?.future;
    return Fragment$ChapterDto(
      id: chapterId,
      mangaId: 7,
      name: 'c1',
      chapterNumber: 1,
      sourceOrder: 1,
      isRead: false,
      isBookmarked: false,
      isDownloaded: true,
      lastPageRead: 0,
      pageCount: 1,
      fetchedAt: '0',
      uploadDate: '0',
      lastReadAt: '0',
      url: '',
      meta: const [],
    );
  }
}

void main() {
  late OfflineDatabase db;
  final store = FakePageStore();

  setUp(() {
    OfflineDownloadCoordinator.resetSharedStateForTest();
    db = testOfflineDatabase();
  });
  tearDown(() => db.close());

  // Minimal non-null deps so the triggers reach the start step instead of
  // bailing on a null coordinator/manager.
  OfflineDownloadCoordinator buildCoordinator() => OfflineDownloadCoordinator(
    db: db,
    engine: ChapterDownloadEngine(
      fetchPage: (_) async => throw UnimplementedError(),
      writePage: store,
      refreshAuth: () async => false,
    ),
    store: store,
    resolvePages: (_) async => const [],
  );

  OfflineDownloadManager buildManager() => OfflineDownloadManager(
    db: db,
    store: store,
    fetchPageUrls: (_) async => const [],
    fetchBytes: (_) async => throw UnimplementedError(),
  );

  /// Pump a ProviderScope with offline "enabled" + fake deps, a spy
  /// downloadStarter, and hand back the captured [WidgetRef] + the spy counter.
  Future<({WidgetRef ref, int Function() starts})> harness(
    WidgetTester tester, {
    _MangaRepository? mangaRepository,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var startCalls = 0;
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mangaBookRepositoryProvider.overrideWithValue(
            mangaRepository ?? _MangaRepository(),
          ),
          offlineEnabledProvider.overrideWithValue(true),
          offlineActiveProvider.overrideWithValue(true),
          offlineDatabaseProvider.overrideWithValue(db),
          offlinePathsProvider.overrideWithValue(const OfflinePaths('/tmp/x')),
          offlinePageStoreProvider.overrideWithValue(store),
          offlineDownloadCoordinatorProvider.overrideWithValue(
            buildCoordinator(),
          ),
          offlineDownloadManagerProvider.overrideWithValue(buildManager()),
          downloadStarterProvider.overrideWithValue(
            ({bool userInitiated = false}) async => startCalls++,
          ),
        ],
        child: Consumer(
          builder: (_, ref, _) {
            captured = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    return (ref: captured, starts: () => startCalls);
  }

  testWidgets('reconcileMangaWidget (Download all / unread) starts downloads', (
    tester,
  ) async {
    final h = await harness(tester);
    await tester.runAsync(() => reconcileMangaWidget(h.ref, 1));
    expect(
      h.starts(),
      1,
      reason:
          'the keep-rule trigger must invoke downloadStarterProvider — '
          'this is the bug where "Download all" did nothing on Android',
    );
  });

  testWidgets(
    'reconcileMangaWidget(startDownload: false) queues without starting',
    (tester) async {
      final h = await harness(tester);
      await tester.runAsync(
        () => reconcileMangaWidget(h.ref, 1, startDownload: false),
      );
      expect(
        h.starts(),
        0,
        reason:
            'a caller batching several manga in a row (e.g. a bulk keep-rule '
            'apply) must be able to queue each one without the FGS starting '
            'and draining between them — otherwise its notification never '
            'reflects the batch\'s real total, only whatever tiny snapshot '
            'happened to be queued at each individual restart',
      );
    },
  );

  for (final retry in [false, true]) {
    testWidgets(
      retry
          ? 'explicit retry resets exhausted server fetch attempts'
          : 'saveChapterToDevice (single chapter) starts downloads',
      (tester) async {
        await db.upsertMangaMetadata(
          id: 7,
          title: 'M',
          updatedAt: DateTime(2026),
        );
        await db.upsertChapterMetadata(
          id: 1,
          mangaId: 7,
          name: 'c1',
          chapterIndex: 1,
          isRead: false,
          lastPageRead: 0,
          isBookmarked: false,
          serverIsDownloaded: true,
          pageCount: 1,
          updatedAt: DateTime(2026),
        );
        if (retry) {
          await db.setChapterDeviceState(1, OfflineDeviceState.error);
          for (var attempt = 0; attempt < 3; attempt++) {
            await db.incrementServerFetchAttempts(1);
          }
          expect((await db.chapterById(1))!.serverFetchAttempts, 3);
        }
        final h = await harness(tester);
        await saveChapterToDevice(h.ref, 1);
        final saved = (await db.chapterById(1))!;
        expect(saved.serverFetchAttempts, 0);
        expect(saved.deviceState, OfflineDeviceState.queued);
        expect(
          h.starts(),
          1,
          reason: 'the single-chapter save must invoke downloadStarterProvider',
        );
      },
    );
  }
  testWidgets('delayed manual save preserves a replacement chapter', (
    tester,
  ) async {
    final signals = (await tester.runAsync(
      () async => (requested: Completer<void>(), response: Completer<void>()),
    ))!;
    final requested = signals.requested;
    final response = signals.response;
    final h = await harness(
      tester,
      mangaRepository: _MangaRepository(
        requested: requested,
        response: response,
      ),
    );
    await tester.runAsync(() async {
      await db.upsertMangaMetadata(
        id: 7,
        title: 'M',
        updatedAt: DateTime(2026),
      );
      await db.upsertChapterMetadata(
        id: 1,
        mangaId: 7,
        name: 'c1',
        chapterIndex: 1,
        isRead: false,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: 1,
        updatedAt: DateTime(2026),
      );
      final saving = saveChapterToDevice(h.ref, 1);
      await requested.future.timeout(const Duration(seconds: 10));
      await db.transaction(() async {
        await db.bumpChapterGeneration(1);
        await db.setChapterPinned(1, false);
        await db.setChapterDeviceState(1, OfflineDeviceState.error);
        for (var attempt = 0; attempt < 5; attempt++) {
          await db.incrementServerFetchAttempts(1);
        }
      });
      response.complete();
      await saving;
      final chapter = (await db.chapterById(1))!;
      expect(chapter.downloadGeneration, 1);
      expect(chapter.pinned, isFalse);
      expect(chapter.serverFetchAttempts, 5);
      expect(chapter.deviceState, OfflineDeviceState.error);
      expect(h.starts(), 0);
    });
  });
}
