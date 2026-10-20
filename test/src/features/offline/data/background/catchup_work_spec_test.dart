// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

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

  test('legacy specs and ledgers default queued work to empty', () {
    final spec = CatchupWorkSpec.fromJson({'serverId': 'srv-1'});
    final ledger = CatchupLedger.fromJson({});
    expect(spec.queuedChapters, isEmpty);
    expect(ledger.chapterGenerations, isEmpty);
    expect(ledger.queuedServerRetries, isEmpty);
    expect(ledger.queuedDownloadRetries, isEmpty);
  });

  test('spec round-trips through the store', () async {
    final s = await store();
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
          ),
        ],
      ),
    );

    final back = s.readSpec()!;
    expect(back.serverId, 'srv-1');
    expect(back.storageCapBytes, 5000);
    expect(back.manga.single.keepRule, OfflineKeepRule.nUnread);
    expect(back.manga.single.onDeviceChapterIds, {1, 2});
    expect(back.manga.single.pinnedChapterIds, {2});
    expect(back.keepRuleMangaIds, {7});
  });

  test('clearState drops spec and ledger but keeps the user toggle', () async {
    final s = await store();
    await s.setEnabled(true);
    await s.writeSpec(
      CatchupWorkSpec(
        serverId: 'srv-1',
        wifiOnly: true,
        storageCapEnabled: false,
        storageCapBytes: 0,
        manga: const [],
      ),
    );
    await s.writeLedger('srv-1', const CatchupLedger());

    await s.clearState();
    expect(s.readSpec(), isNull);
    expect(s.readLedger('srv-1').cursor.fetchedAt, 0);
    expect(s.enabled, isTrue);
  });

  test('chapterSortMode round-trips through the spec (alphabetical too), '
      'and defaults to null when absent', () {
    const spec = CatchupMangaSpec(
      mangaId: 1,
      keepRule: OfflineKeepRule.nUnread,
      keepUnreadCount: 3,
      onDeviceChapterIds: {},
      pinnedChapterIds: {},
      chapterSortMode: ChapterSortAxis.uploadedAt,
    );
    final restored = CatchupMangaSpec.fromJson(
      jsonDecode(jsonEncode(spec.toJson())) as Map<String, Object?>,
    );
    expect(restored.chapterSortMode, ChapterSortAxis.uploadedAt);

    // The Tsumiru-only axis survives the hop to the background worker too.
    final alphabetical = CatchupMangaSpec.fromJson(
      jsonDecode(
            jsonEncode(
              const CatchupMangaSpec(
                mangaId: 1,
                keepRule: OfflineKeepRule.nUnread,
                keepUnreadCount: 3,
                onDeviceChapterIds: {},
                pinnedChapterIds: {},
                chapterSortMode: ChapterSortAxis.alphabetical,
              ).toJson(),
            ),
          )
          as Map<String, Object?>,
    );
    expect(alphabetical.chapterSortMode, ChapterSortAxis.alphabetical);

    // Legacy/unset spec (written before this field existed, or a manga with
    // no webUI_sortBy meta) must not throw and must default to null, not to
    // some fallback axis — the caller's own null-fallback logic decides.
    final legacy = CatchupMangaSpec.fromJson({
      'mangaId': 1,
      'keepRule': 'nUnread',
      'keepUnreadCount': 3,
    });
    expect(legacy.chapterSortMode, isNull);
  });
}
