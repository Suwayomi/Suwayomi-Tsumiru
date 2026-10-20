// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/offline_types.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<CatchupStateStore> store() async {
    SharedPreferences.setMockInitialValues(const {});
    return CatchupStateStore(await SharedPreferences.getInstance());
  }

  test('spec and ledger round-trip through the store', () async {
    // Legacy payloads default queued work to empty.
    final legacySpec = CatchupWorkSpec.fromJson({'serverId': 'srv-1'});
    final legacyLedger = CatchupLedger.fromJson({});
    expect(legacySpec.queuedChapters, isEmpty);
    expect(legacyLedger.chapterGenerations, isEmpty);
    expect(legacyLedger.queuedServerRetries, isEmpty);
    expect(legacyLedger.queuedDownloadRetries, isEmpty);

    final s = await store();
    await s.setEnabled(true);
    await s.writeSpec(
      CatchupWorkSpec(
        serverId: 'srv-1',
        wifiOnly: true,
        storageCapEnabled: true,
        storageCapBytes: 5000,
        manga: [
          const CatchupMangaSpec(
            mangaId: 7,
            keepRule: OfflineKeepRule.nUnread,
            keepUnreadCount: 3,
            onDeviceChapterIds: {1, 2},
            pinnedChapterIds: {2},
            chapterSortMode: ChapterSortAxis.alphabetical,
          ),
        ],
      ),
    );
    await s.writeLedger('srv-1', const CatchupLedger());

    final back = s.readSpec()!;
    expect(back.serverId, 'srv-1');
    expect(back.storageCapBytes, 5000);
    expect(back.manga.single.keepRule, OfflineKeepRule.nUnread);
    expect(back.manga.single.onDeviceChapterIds, {1, 2});
    expect(back.manga.single.pinnedChapterIds, {2});
    expect(back.manga.single.chapterSortMode, ChapterSortAxis.alphabetical);
    expect(back.keepRuleMangaIds, {7});

    // An unset sort axis decodes as null, leaving the caller's fallback.
    final legacyManga = CatchupMangaSpec.fromJson({
      'mangaId': 1,
      'keepRule': 'nUnread',
      'keepUnreadCount': 3,
    });
    expect(legacyManga.chapterSortMode, isNull);

    await s.clearState();
    expect(s.readSpec(), isNull);
    expect(s.readLedger('srv-1').cursor.fetchedAt, 0);
    expect(s.enabled, isTrue);
  });
}
