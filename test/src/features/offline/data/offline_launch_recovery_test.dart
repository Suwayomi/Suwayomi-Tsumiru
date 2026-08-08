// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Android reaches disk-vs-catalog recovery through the background worker's
// launch replay. Every other platform has no replay at all, so the launch path
// has to run it — without this a chapter whose commit landed but whose catalog
// write didn't gets downloaded all over again, and files left behind by a
// crashed delete are never swept.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/offline/data/chapter_commit.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/features/offline/data/offline_background_downloads.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_coordinator.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

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

  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineEnabledProvider.overrideWithValue(true),
        offlineActiveProvider.overrideWithValue(true),
        offlineDatabaseProvider.overrideWithValue(db),
        offlinePathsProvider.overrideWithValue(const OfflinePaths('/tmp/x')),
        offlinePageStoreProvider.overrideWithValue(store),
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
      ],
    );
  }

  Future<void> seedChapter(int id, int mangaId) => db.upsertChapterMetadata(
    id: id,
    mangaId: mangaId,
    name: 'c$id',
    chapterIndex: 1,
    isRead: false,
    lastPageRead: 0,
    isBookmarked: false,
    serverIsDownloaded: true,
    pageCount: 2,
    updatedAt: DateTime(2026),
  );

  test(
    'launch adopts a chapter whose commit landed but was never recorded',
    () async {
      await seedChapter(1, 7);
      await db.setChapterDeviceState(1, OfflineDeviceState.downloading);
      // The rename happened; the catalog write didn't.
      store.seedCommitted(1, {0: 5, 1: 5});

      await initOfflineDownloads(await container());

      expect(
        (await db.chapterById(1))!.deviceState,
        OfflineDeviceState.downloaded,
      );
      expect(await db.downloadedPageCount(1), 2);
      expect(store.written, isEmpty, reason: 'nothing was re-downloaded');
    },
  );

  test('launch sweeps files left behind by a crashed delete', () async {
    await seedChapter(1, 7);
    await db.setChapterDeviceState(1, OfflineDeviceState.none);
    store.seedCommitted(1, {0: 5, 1: 5});

    await initOfflineDownloads(await container());

    expect(store.deletedChapters, contains(1));
    expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.none);
  });

  test('a chapter left only in the set-aside slot comes back', () async {
    // A kill mid-replacement parks the old copy aside; a failed download then
    // clears the staging that was going to replace it. The set-aside copy is
    // now the only one, under a row still saying downloaded — so recovery has
    // to restore it, not ignore it.
    await seedChapter(1, 7);
    await db.setChapterDeviceState(1, OfflineDeviceState.downloaded);
    store.seedCommitted(1, {0: 5, 1: 5});
    store.setAside(1);

    await initOfflineDownloads(await container());

    expect(
      store.committed.containsKey(1),
      isTrue,
      reason: 'the only copy is put back',
    );
    expect(store.superseded.containsKey(1), isFalse);
    expect(
      (await db.chapterById(1))!.deviceState,
      OfflineDeviceState.downloaded,
    );
  });

  test('a set-aside copy never outranks a complete staging', () async {
    // Both present means the kill landed between the two renames: staging was
    // verified complete a moment earlier, so it is the newer copy and the one
    // that must land.
    await seedChapter(1, 7);
    await db.setChapterDeviceState(1, OfflineDeviceState.downloading);
    store.seedCommitted(1, {0: 5, 1: 5});
    store.setAside(1);
    store.seedStaged(1, {0: 9, 1: 9, 2: 9}, indices: [0, 1, 2]);

    await initOfflineDownloads(await container());

    expect(
      await db.downloadedPageCount(1),
      3,
      reason: 'the newer download landed, not the set-aside copy',
    );
    expect(
      (await db.chapterById(1))!.deviceState,
      OfflineDeviceState.downloaded,
    );
  });
}
