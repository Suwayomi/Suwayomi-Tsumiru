// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/notifications/domain/new_chapter_detection.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_paths.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/offline_types.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('non-account worker storage survives spec persistence', () {
    final spec = CatchupWorkSpec.fromJson({
      'serverId': 'basic-server',
      'nonAccountScoped': true,
    });
    final restored = CatchupWorkSpec.fromJson(spec.toJson());
    expect(restored.storagePath('/offline'), '/offline/non-account');
    expect(offlineControlRoot(restored.storagePath('/offline')), '/offline');
    expect(
      CatchupWorkSpec.fromJson({'serverId': 'legacy'}).storagePath('/offline'),
      '/offline',
    );
    expect(offlineControlRoot('/offline/accounts/non-account'), '/offline');
    expect(isNonAccountStoragePath('/offline/accounts/non-account'), isFalse);
  });

  Future<CatchupStateStore> store() async {
    SharedPreferences.setMockInitialValues(const {});
    return CatchupStateStore(await SharedPreferences.getInstance());
  }

  test('server attempt snapshots round-trip and default to zero', () {
    const queued = QueuedChapterSpec(
      chapterId: 5,
      mangaId: 1,
      generation: 2,
      serverFetchAttempts: 4,
    );
    expect(QueuedChapterSpec.fromJson(queued.toJson()).serverFetchAttempts, 4);
    expect(
      QueuedChapterSpec.fromJson({
        'chapterId': 5,
        'mangaId': 1,
        'generation': 2,
      }).serverFetchAttempts,
      0,
    );
    const manga = CatchupMangaSpec(
      mangaId: 1,
      keepRule: OfflineKeepRule.all,
      keepUnreadCount: 3,
      onDeviceChapterIds: {},
      pinnedChapterIds: {},
      chapterGenerations: {5: 2},
      serverFetchAttempts: {5: 4},
    );
    final restored = CatchupMangaSpec.fromJson(manga.toJson());
    expect(restored.serverFetchAttempts, {5: 4});
    expect(restored.generationOf(5), 2);
    expect(
      CatchupMangaSpec.fromJson({'mangaId': 1}).serverFetchAttempts,
      isEmpty,
    );
  });

  test(
    'failed chapter ids round-trip and legacy manga specs default empty',
    () {
      const spec = CatchupMangaSpec(
        mangaId: 1,
        keepRule: OfflineKeepRule.all,
        keepUnreadCount: 3,
        onDeviceChapterIds: {},
        pinnedChapterIds: {},
        failedChapterIds: {5, 7},
      );
      final restored = CatchupMangaSpec.fromJson(
        jsonDecode(jsonEncode(spec.toJson())) as Map<String, Object?>,
      );
      expect(restored.failedChapterIds, {5, 7});
      expect(
        CatchupMangaSpec.fromJson({'mangaId': 1}).failedChapterIds,
        isEmpty,
      );
    },
  );

  test('queued chapters round-trip with generation-specific keys', () async {
    final s = await store();
    await s.writeSpec(
      const CatchupWorkSpec(
        serverId: 'srv-1',
        wifiOnly: true,
        storageCapEnabled: false,
        storageCapBytes: 0,
        manga: [],
        queuedChapters: [
          QueuedChapterSpec(chapterId: 42, mangaId: 7, generation: 2),
          QueuedChapterSpec(chapterId: 42, mangaId: 7, generation: 3),
        ],
      ),
    );
    final queued = s.readSpec()!.queuedChapters;
    expect(queued.map((chapter) => chapter.key), ['42:2', '42:3']);
    expect(queued.first.chapterId, 42);
    expect(queued.first.mangaId, 7);
    expect(queued.first.generation, 2);
  });

  test('legacy specs and ledgers default queued work to empty', () {
    final spec = CatchupWorkSpec.fromJson({'serverId': 'srv-1'});
    final ledger = CatchupLedger.fromJson({});
    expect(spec.queuedChapters, isEmpty);
    expect(ledger.chapterGenerations, isEmpty);
    expect(ledger.queuedServerRetries, isEmpty);
    expect(ledger.queuedDownloadRetries, isEmpty);
  });

  test('queued retries round-trip independently for each generation', () async {
    final s = await store();
    const ledger = CatchupLedger(
      queuedServerRetries: {'42:2': 3},
      queuedDownloadRetries: {'42:2': 1, '42:3': 0},
    );
    await s.writeLedger('srv-1', ledger.copyWith());
    final restored = s.readLedger('srv-1');
    expect(restored.queuedServerRetries, {'42:2': 3});
    expect(restored.queuedDownloadRetries, {'42:2': 1, '42:3': 0});
    final updated = restored.copyWith(
      queuedServerRetries: {'42:3': 1},
      queuedDownloadRetries: {'42:3': 2},
    );
    expect(updated.queuedServerRetries, {'42:3': 1});
    expect(updated.queuedDownloadRetries, {'42:3': 2});
  });

  test('paused reads the persisted offline pause setting', () async {
    final s = await store();
    expect(s.paused, isFalse);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('offlineDownloadsPaused', true);
    await s.reload();
    expect(s.paused, isTrue);
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
        chapterGenerations: {10: 1, 12: 2},
      ),
    );

    final same = s.readLedger('srv-1');
    expect(same.cursor.fetchedAt, 999);
    expect(same.cursor.recent, {5: 999});
    expect(same.pendingDownloads, {10: 1, 11: 1});
    expect(same.pendingServerFetch, {12: 2});
    expect(same.serverFetchRetries, {12: 3});
    expect(same.chapterGenerations, {10: 1, 12: 2});
    expect(same.copyWith().chapterGenerations, same.chapterGenerations);
    expect(same.copyWith(chapterGenerations: {}).chapterGenerations, isEmpty);

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

  test('catalogServerId reads the offline catalog key, not a made-up '
      'namespace the executor could mismatch against', () async {
    SharedPreferences.setMockInitialValues({
      'offlineCatalogServerId': 'catalog-uuid-123',
    });
    final s = CatchupStateStore(await SharedPreferences.getInstance());
    expect(s.catalogServerId, 'catalog-uuid-123');
  });

  test(
    'catalogServerId is null when the offline catalog was never set up',
    () async {
      final s = await store();
      expect(s.catalogServerId, isNull);
    },
  );

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

  test(
    'downloadEnabled defaults to true, matching pre-toggle behavior',
    () async {
      final s = await store();
      expect(s.downloadEnabled, isTrue);
    },
  );

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

  test('an unrecognized chapterSortMode string degrades to null, not a '
      'crash — same resilience as the unknown keep-rule case above', () {
    final restored = CatchupMangaSpec.fromJson({
      'mangaId': 1,
      'keepRule': 'nUnread',
      'keepUnreadCount': 3,
      'chapterSortMode': 'someFutureAxis',
    });
    expect(restored.chapterSortMode, isNull);
  });
}
