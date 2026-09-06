// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  test('returns manga ids with at least one downloaded chapter', () async {
    await db.upsertChapterMetadata(id: 1, mangaId: 10, name: 'a', chapterIndex: 1,
      isRead: false, lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
      pageCount: 1, updatedAt: DateTime(2026));
    await db.upsertChapterMetadata(id: 2, mangaId: 20, name: 'b', chapterIndex: 1,
      isRead: false, lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
      pageCount: 1, updatedAt: DateTime(2026));
    await db.setChapterDeviceState(1, OfflineDeviceState.downloaded, bytes: 5);
    expect(await db.mangaIdsWithDeviceDownloads(), {10});
  });

  group('watchMangaIdsWithDeviceDownloads', () {
    test(
      'emits an updated set live as chapters finish downloading elsewhere, '
      'instead of only reflecting a one-time snapshot',
      () async {
        await db.upsertChapterMetadata(id: 1, mangaId: 10, name: 'a', chapterIndex: 1,
          isRead: false, lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
          pageCount: 1, updatedAt: DateTime(2026));
        await db.upsertChapterMetadata(id: 2, mangaId: 20, name: 'b', chapterIndex: 1,
          isRead: false, lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
          pageCount: 1, updatedAt: DateTime(2026));

        final emissions = <Set<int>>[];
        final sub = db.watchMangaIdsWithDeviceDownloads().listen(emissions.add);
        addTearDown(sub.cancel);

        await pumpEventQueue();
        expect(emissions.last, isEmpty,
            reason: 'nothing downloaded yet');

        // A chapter finishes downloading -- simulates the moment
        // commitStagedChapter() flips deviceState, whether that happened from
        // the manga details page, the Downloads screen, or the background
        // catch-up pass.
        await db.setChapterDeviceState(1, OfflineDeviceState.downloaded, bytes: 5);
        await pumpEventQueue();
        expect(emissions.last, {10},
            reason: 'the stream must notice the finished download without '
                'anything re-reading it manually');

        await db.setChapterDeviceState(2, OfflineDeviceState.downloaded, bytes: 5);
        await pumpEventQueue();
        expect(emissions.last, {10, 20});
      },
    );

    test('matches mangaIdsWithDeviceDownloads for the same state', () async {
      await db.upsertChapterMetadata(id: 1, mangaId: 10, name: 'a', chapterIndex: 1,
        isRead: false, lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
        pageCount: 1, updatedAt: DateTime(2026));
      await db.setChapterDeviceState(1, OfflineDeviceState.downloaded, bytes: 5);

      final oneShot = await db.mangaIdsWithDeviceDownloads();
      final live = await db.watchMangaIdsWithDeviceDownloads().first;
      expect(live, oneShot);
    });
  });

  group('offlineDeviceMangaIdsProvider (end-to-end through Riverpod)', () {
    test(
      'updates live when a chapter finishes downloading, without anything '
      'invalidating or re-reading the provider',
      () async {
        await db.upsertChapterMetadata(id: 1, mangaId: 10, name: 'a', chapterIndex: 1,
          isRead: false, lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
          pageCount: 1, updatedAt: DateTime(2026));

        final container = ProviderContainer(overrides: [
          offlineEnabledProvider.overrideWithValue(true),
          offlineDatabaseProvider.overrideWithValue(db),
          offlinePathsProvider.overrideWithValue(const OfflinePaths('/tmp/x')),
        ]);
        addTearDown(container.dispose);

        final emissions = <Set<int>>[];
        container.listen(
          offlineDeviceMangaIdsProvider,
          (prev, next) {
            final value = next.value;
            if (value != null) emissions.add(value);
          },
          fireImmediately: true,
        );

        await pumpEventQueue();
        expect(emissions.last, isEmpty);

        // This is the exact user-facing bug: a chapter finishing its download
        // -- from the manga details page, the Downloads screen, or the
        // background catch-up pass, it doesn't matter which -- must be
        // reflected on the Library screen's "on device" badge/filter without
        // needing a manual refresh or re-navigation.
        await db.setChapterDeviceState(1, OfflineDeviceState.downloaded, bytes: 5);
        await pumpEventQueue();

        expect(emissions.last, {10},
            reason: 'the provider must pick up the change live; before this '
                'fix it only ever reflected whatever was on device the '
                'moment it was first built');
      },
    );
  });
}
