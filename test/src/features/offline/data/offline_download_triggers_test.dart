// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Regression guard for the bug where "Download all / unread" silently did
// nothing on Android: the trigger queued chapters but never started the
// download service. Every download trigger MUST go through
// downloadStarterProvider — these tests fail if one forgets to.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/features/offline/data/offline_background_downloads.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_coordinator.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_manager.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../../helpers/offline_test_db.dart';

class _FakeStore implements OfflinePageStore {
  @override
  Future<({String relPath, int bytes})> writePage(
          int m, int c, int i, List<int> b, String e) async =>
      (relPath: '$m/$c/$i.$e', bytes: b.length);
  @override
  Future<void> deleteChapter(int m, int c) async {}
  @override
  Future<int> chapterBytes(int m, int c) async => 0;
}

void main() {
  late OfflineDatabase db;
  final store = _FakeStore();

  setUp(() => db = testOfflineDatabase());
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
        resolvePages: (_) async => const [],
        measureChapterBytes: (_, __) async => 0,
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
      WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var startCalls = 0;
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          offlineEnabledProvider.overrideWithValue(true),
          offlineDatabaseProvider.overrideWithValue(db),
          offlinePathsProvider.overrideWithValue(const OfflinePaths('/tmp/x')),
          offlinePageStoreProvider.overrideWithValue(store),
          offlineDownloadCoordinatorProvider
              .overrideWithValue(buildCoordinator()),
          offlineDownloadManagerProvider.overrideWithValue(buildManager()),
          downloadStarterProvider.overrideWithValue(() async => startCalls++),
        ],
        child: Consumer(builder: (_, ref, __) {
          captured = ref;
          return const SizedBox();
        }),
      ),
    );
    return (ref: captured, starts: () => startCalls);
  }

  testWidgets('reconcileMangaWidget (Download all / unread) starts downloads',
      (tester) async {
    final h = await harness(tester);
    await reconcileMangaWidget(h.ref, 1);
    expect(h.starts(), 1,
        reason: 'the keep-rule trigger must invoke downloadStarterProvider — '
            'this is the bug where "Download all" did nothing on Android');
  });

  testWidgets('saveChapterToDevice (single chapter) starts downloads',
      (tester) async {
    await db.upsertMangaMetadata(
        id: 7, title: 'M', updatedAt: DateTime(2026));
    await db.upsertChapterMetadata(
        id: 1, mangaId: 7, name: 'c1', chapterIndex: 1, isRead: false,
        lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
        pageCount: 1, updatedAt: DateTime(2026));
    final h = await harness(tester);
    await saveChapterToDevice(h.ref, 1);
    expect(h.starts(), 1,
        reason: 'the single-chapter save must invoke downloadStarterProvider');
  });
}
