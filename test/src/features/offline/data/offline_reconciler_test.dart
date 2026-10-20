// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_reconciler.dart';
import 'package:tsumiru/src/features/offline/data/reconcile_types.dart';
import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  Future<void> seedChapter(
    int id,
    int idx, {
    bool read = false,
    bool serverDl = true,
    OfflineDeviceState dev = OfflineDeviceState.none,
    int bytes = 10,
    DateTime? downloadedAt,
    bool pinned = false,
  }) async {
    await db.upsertChapterMetadata(
      id: id,
      mangaId: 1,
      name: 'c$id',
      chapterIndex: idx,
      isRead: read,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: serverDl,
      pageCount: 1,
      updatedAt: DateTime(2026),
    );
    if (dev != OfflineDeviceState.none) {
      await db.setChapterDeviceState(
        id,
        dev,
        bytes: bytes,
        downloadedAt: downloadedAt ?? DateTime(2026, 1, 1),
      );
    }
    if (pinned) await db.setChapterPinned(id, true);
  }

  // ── base brief tests ────────────────────────────────────────────────────────

  test(
    'downloads desired-but-missing on-server chapters; skips not-on-server',
    () async {
      await db.upsertMangaMetadata(
        id: 1,
        title: 'M',
        updatedAt: DateTime(2026),
      );
      await db.setKeepRule(1, OfflineKeepRule.allUnread, 3);
      await seedChapter(1, 1, read: false, serverDl: true);
      await seedChapter(2, 2, read: false, serverDl: false); // unsatisfiable
      final downloaded = <int>[];
      final evicted = <int>[];
      final r = await OfflineReconciler(
        db: db,
        nets: SafetyNetConfig.off,
        onDownload: (id) async => downloaded.add(id),
        onEvict: (id) async => evicted.add(id),
        now: DateTime(2026, 3, 1),
      ).reconcileManga(1);
      expect(downloaded, [1]); // ch1 desired + on server
      expect(evicted, isEmpty);
      expect(r.toDownload, {1});
    },
  );

  test(
    'exhausted server retries fail the pending generation and preserve completed copies',
    () async {
      await db.upsertMangaMetadata(
        id: 1,
        title: 'M',
        updatedAt: DateTime(2026),
      );
      await db.setKeepRule(1, OfflineKeepRule.all, 3);
      await seedChapter(1, 1, serverDl: false);
      await seedChapter(
        2,
        2,
        serverDl: false,
        dev: OfflineDeviceState.downloaded,
      );
      await db.bumpChapterGeneration(1);
      for (var attempt = 0; attempt < 5; attempt++) {
        await db.incrementServerFetchAttempts(1);
        await db.incrementServerFetchAttempts(2);
      }
      final before = (await db.chapterById(1))!;
      final server = <int>{};
      final device = <int>[];
      await OfflineReconciler(
        db: db,
        nets: SafetyNetConfig.off,
        onDownload: (id) async => device.add(id),
        onEvict: (_) async {},
        now: DateTime(2026),
        onServerDownload: (ids) async => server.addAll(ids),
      ).reconcileManga(1);
      final failed = (await db.chapterById(1))!;
      expect(failed.deviceState, OfflineDeviceState.error);
      expect(failed.downloadGeneration, before.downloadGeneration);
      expect(failed.serverFetchAttempts, 5);
      expect(
        (await db.chapterById(2))!.deviceState,
        OfflineDeviceState.downloaded,
      );
      expect(server, isEmpty);
      expect(device, isEmpty);
    },
  );

  test('terminal error never re-enqueues a missing server chapter', () async {
    await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
    await db.setKeepRule(1, OfflineKeepRule.allUnread, 3);
    await seedChapter(1, 1, serverDl: false, dev: OfflineDeviceState.error);
    final enqueued = <int>{};
    await OfflineReconciler(
      db: db,
      nets: SafetyNetConfig.off,
      onDownload: (_) async {},
      onEvict: (_) async {},
      now: DateTime(2026),
      onServerDownload: (ids) async => enqueued.addAll(ids),
    ).reconcileManga(1);
    expect(enqueued, isEmpty);
    expect((await db.chapterById(1))!.serverFetchAttempts, 0);
  });

  test('evicts a downloaded chapter no longer desired', () async {
    await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
    await db.setKeepRule(1, OfflineKeepRule.allUnread, 3);
    await seedChapter(
      1,
      1,
      read: true,
      dev: OfflineDeviceState.downloaded,
    ); // read -> not desired
    final downloaded = <int>[];
    final evicted = <int>[];
    await OfflineReconciler(
      db: db,
      nets: SafetyNetConfig.off,
      onDownload: (id) async => downloaded.add(id),
      onEvict: (id) async => evicted.add(id),
      now: DateTime(2026, 3, 1),
    ).reconcileManga(1);
    expect(evicted, [1]);
    expect(downloaded, isEmpty);
  });

  // ── RC6: orphaned chapters are evicted ──────────────────────────────────────

  // ── RC5: convergence under storage cap ──────────────────────────────────────

  // ── RC5-cold: cap gating works with zero downloaded chapters ───────────────

  test(
    'RC5-cold: cold-start cap hole — first pass queues only a bounded subset',
    () async {
      // With no downloaded chapters, the page-count estimate exceeds the cap.
      const kBytesPerPage = 256 * 1024; // must match _estimatedBytesPerPage
      const pageCount = 5; // per chapter
      const estimatedChapterBytes = pageCount * kBytesPerPage; // 1.28 MB
      const cap = SafetyNetConfig(
        timeEvictEnabled: false,
        keepDays: 30,
        storageCapEnabled: true,
        storageCapBytes: 600 * 1024, // 600 KB — less than one estimated chapter
      );

      await db.upsertMangaMetadata(
        id: 1,
        title: 'M',
        updatedAt: DateTime(2026),
      );
      await db.setKeepRule(1, OfflineKeepRule.all, 0);

      // 5 chapters: all on server, none on device yet.
      for (var i = 1; i <= 5; i++) {
        await db.upsertChapterMetadata(
          id: i,
          mangaId: 1,
          name: 'c$i',
          chapterIndex: i,
          isRead: false,
          lastPageRead: 0,
          isBookmarked: false,
          serverIsDownloaded: true,
          pageCount: pageCount,
          updatedAt: DateTime(2026),
        );
      }

      final downloaded1 = <int>[];
      final r1 = await OfflineReconciler(
        db: db,
        nets: cap,
        onDownload: (id) async => downloaded1.add(id),
        onEvict: (id) async {},
        now: DateTime(2026, 3, 1),
      ).reconcileManga(1);

      // With a 600 KB cap and each chapter estimated at ~1.28 MB, none fit.
      expect(
        r1.toDownload.length,
        lessThan(5),
        reason:
            'cold-start cap guard must bound downloads below total chapter count',
      );
      // Specifically 0 chapters fit (cap < estimate).
      expect(
        r1.toDownload,
        isEmpty,
        reason:
            'cap (600 KB) < one estimated chapter (${estimatedChapterBytes ~/ 1024} KB) — nothing fits',
      );

      // Second pass: state is unchanged (nothing was downloaded), so still empty.
      final r2 = await OfflineReconciler(
        db: db,
        nets: cap,
        onDownload: (id) async {},
        onEvict: (id) async {},
        now: DateTime(2026, 3, 1),
      ).reconcileManga(1);
      expect(r2.toDownload, isEmpty, reason: 'no oscillation on second pass');
    },
  );

  // ── downloadProtectionWindow: re-download missing keep-window chapters ──────
}
