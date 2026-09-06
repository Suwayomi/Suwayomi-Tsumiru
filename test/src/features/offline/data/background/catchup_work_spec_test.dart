// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/notifications/domain/new_chapter_detection.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/offline_types.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<CatchupStateStore> store() async {
    SharedPreferences.setMockInitialValues(const {});
    return CatchupStateStore(await SharedPreferences.getInstance());
  }

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

  test('an unknown keep-rule name degrades to off, not a crash', () async {
    final s = await store();
    // A spec written by a future app version with a new rule value.
    SharedPreferences.setMockInitialValues({
      'catchup_work_spec':
          '{"serverId":"srv-1","wifiOnly":true,"storageCapEnabled":false,'
          '"storageCapBytes":0,"manga":[{"mangaId":1,"keepRule":"someFutureRule",'
          '"keepUnreadCount":0,"onDevice":[],"pinned":[]}]}',
    });
    final s2 = CatchupStateStore(await SharedPreferences.getInstance());
    expect(s2.readSpec()!.manga.single.keepRule, OfflineKeepRule.off);
    expect(s.readSpec, returnsNormally);
  });

  test('ledger round-trips and is scoped to its server', () async {
    final s = await store();
    await s.writeLedger(
      'srv-1',
      const CatchupLedger(
        cursor: NewChapterWatermark(fetchedAt: 999, recent: {5: 999}),
        pendingDownloads: {10: 1, 11: 1},
        pendingServerFetch: {12: 2},
        serverFetchRetries: {12: 3},
      ),
    );

    final same = s.readLedger('srv-1');
    expect(same.cursor.fetchedAt, 999);
    expect(same.cursor.recent, {5: 999});
    expect(same.pendingDownloads, {10: 1, 11: 1});
    expect(same.pendingServerFetch, {12: 2});
    expect(same.serverFetchRetries, {12: 3});

    // A server switch must start from scratch, never replay another server's
    // ledger against colliding integer ids.
    final other = s.readLedger('srv-2');
    expect(other.cursor.fetchedAt, 0);
    expect(other.pendingDownloads, isEmpty);
  });

  test('backfilledMangaIds round-trips through the ledger', () async {
    final s = await store();
    await s.writeLedger(
      'srv-1',
      const CatchupLedger(backfilledMangaIds: {7, 9}),
    );

    expect(s.readLedger('srv-1').backfilledMangaIds, {7, 9});
    // A server switch must not carry another server's backfill history —
    // same isolation rule as every other field on this ledger.
    expect(s.readLedger('srv-2').backfilledMangaIds, isEmpty);
  });

  test(
      'catalogServerId reads the offline catalog key, not a made-up '
      'namespace the executor could mismatch against', () async {
    SharedPreferences.setMockInitialValues({
      'offlineCatalogServerId': 'catalog-uuid-123',
    });
    final s = CatchupStateStore(await SharedPreferences.getInstance());
    expect(s.catalogServerId, 'catalog-uuid-123');
  });

  test('catalogServerId is null when the offline catalog was never set up',
      () async {
    final s = await store();
    expect(s.catalogServerId, isNull);
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

  test('downloadEnabled defaults to true, matching pre-toggle behavior',
      () async {
    final s = await store();
    expect(s.downloadEnabled, isTrue);
  });

  test('downloadEnabled round-trips and survives clearState', () async {
    final s = await store();
    await s.setDownloadEnabled(false);
    expect(s.downloadEnabled, isFalse);

    await s.clearState();
    expect(s.downloadEnabled, isFalse);
  });

  test('chapter generations survive the spec round-trip', () {
    // A chapter deleted once carries a bumped generation. Staging written at
    // the wrong one is rejected at launch AFTER the obligation has been struck
    // off the ledger, so the download is simply lost.
    const spec = CatchupMangaSpec(
      mangaId: 1,
      keepRule: OfflineKeepRule.all,
      keepUnreadCount: 3,
      onDeviceChapterIds: {},
      pinnedChapterIds: {},
      chapterGenerations: {42: 3},
    );

    final restored = CatchupMangaSpec.fromJson(
      jsonDecode(jsonEncode(spec.toJson())) as Map<String, Object?>,
    );

    expect(restored.generationOf(42), 3);
    expect(
      restored.generationOf(99),
      0,
      reason: 'a chapter nobody deleted defaults to 0',
    );
  });
}
