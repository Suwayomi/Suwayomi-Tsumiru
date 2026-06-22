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

  Future<void> seedChapter(int id, int idx, {
    bool read = false,
    bool serverDl = true,
    OfflineDeviceState dev = OfflineDeviceState.none,
    int bytes = 10,
    DateTime? downloadedAt,
    bool pinned = false,
  }) async {
    await db.upsertChapterMetadata(
      id: id, mangaId: 1, name: 'c$id', chapterIndex: idx, isRead: read,
      lastPageRead: 0, isBookmarked: false, serverIsDownloaded: serverDl,
      pageCount: 1, updatedAt: DateTime(2026));
    if (dev != OfflineDeviceState.none) {
      await db.setChapterDeviceState(id, dev,
          bytes: bytes, downloadedAt: downloadedAt ?? DateTime(2026, 1, 1));
    }
    if (pinned) await db.setChapterPinned(id, true);
  }

  // ── base brief tests ────────────────────────────────────────────────────────

  test('downloads desired-but-missing on-server chapters; skips not-on-server', () async {
    await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
    await db.setKeepRule(1, OfflineKeepRule.allUnread, 3);
    await seedChapter(1, 1, read: false, serverDl: true);
    await seedChapter(2, 2, read: false, serverDl: false); // unsatisfiable
    final downloaded = <int>[]; final evicted = <int>[];
    final r = await OfflineReconciler(
      db: db, nets: SafetyNetConfig.off,
      onDownload: (id) async => downloaded.add(id),
      onEvict: (id) async => evicted.add(id),
      now: DateTime(2026, 3, 1),
    ).reconcileManga(1);
    expect(downloaded, [1]);     // ch1 desired + on server
    expect(evicted, isEmpty);
    expect(r.toDownload, {1});
  });

  test('evicts a downloaded chapter no longer desired', () async {
    await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
    await db.setKeepRule(1, OfflineKeepRule.allUnread, 3);
    await seedChapter(1, 1, read: true, dev: OfflineDeviceState.downloaded); // read -> not desired
    final downloaded = <int>[]; final evicted = <int>[];
    await OfflineReconciler(
      db: db, nets: SafetyNetConfig.off,
      onDownload: (id) async => downloaded.add(id),
      onEvict: (id) async => evicted.add(id),
      now: DateTime(2026, 3, 1),
    ).reconcileManga(1);
    expect(evicted, [1]);
    expect(downloaded, isEmpty);
  });

  // ── RC6: orphaned chapters are evicted ──────────────────────────────────────

  test('RC6: orphaned chapter is included in evict and onEvict is called', () async {
    await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
    await db.setKeepRule(1, OfflineKeepRule.allUnread, 3);
    // An orphaned chapter (server-gone): was downloaded, now marked orphaned.
    await seedChapter(10, 10, read: false, serverDl: false, dev: OfflineDeviceState.orphaned);
    final evicted = <int>[];
    final r = await OfflineReconciler(
      db: db, nets: SafetyNetConfig.off,
      onDownload: (id) async {},
      onEvict: (id) async => evicted.add(id),
      now: DateTime(2026, 3, 1),
    ).reconcileManga(1);
    expect(evicted, contains(10));
    expect(r.toEvict, contains(10));
  });

  // ── RC5: convergence under storage cap ──────────────────────────────────────

  // ── RC5-cold: cap gating works with zero downloaded chapters ───────────────

  test('RC5-cold: cold-start cap hole — first pass queues only a bounded subset', () async {
    // Bug: when avgBytes == 0 (no downloaded chapters yet), the estimate was
    // always 0, so projectedBytes never grew and the cap guard was a no-op,
    // causing EVERY chapter to be queued on the first pass.
    //
    // Fix: fall back to pageCount * _estimatedBytesPerPage (5 pages * 256 KB =
    // 1.28 MB per chapter).  With a 600 KB cap, at most 0 chapters fit (the
    // first candidate already exceeds the cap), so toDownload must be empty.
    const kBytesPerPage = 256 * 1024; // must match _estimatedBytesPerPage
    const pageCount = 5; // per chapter
    const estimatedChapterBytes = pageCount * kBytesPerPage; // 1.28 MB
    const cap = SafetyNetConfig(
      timeEvictEnabled: false,
      keepDays: 30,
      storageCapEnabled: true,
      storageCapBytes: 600 * 1024, // 600 KB — less than one estimated chapter
    );

    await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
    await db.setKeepRule(1, OfflineKeepRule.all, 0);

    // 5 chapters: all on server, none on device yet.
    for (var i = 1; i <= 5; i++) {
      await db.upsertChapterMetadata(
        id: i, mangaId: 1, name: 'c$i', chapterIndex: i,
        isRead: false, lastPageRead: 0, isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: pageCount, updatedAt: DateTime(2026),
      );
    }

    final downloaded1 = <int>[];
    final r1 = await OfflineReconciler(
      db: db, nets: cap,
      onDownload: (id) async => downloaded1.add(id),
      onEvict: (id) async {},
      now: DateTime(2026, 3, 1),
    ).reconcileManga(1);

    // With a 600 KB cap and each chapter estimated at ~1.28 MB, none fit.
    // Pre-fix this was 5 (all queued). The fix must make it 0.
    expect(
      r1.toDownload.length,
      lessThan(5),
      reason: 'cold-start cap guard must bound downloads below total chapter count',
    );
    // Specifically 0 chapters fit (cap < estimate).
    expect(
      r1.toDownload,
      isEmpty,
      reason: 'cap (600 KB) < one estimated chapter (${estimatedChapterBytes ~/ 1024} KB) — nothing fits',
    );

    // Second pass: state is unchanged (nothing was downloaded), so still empty.
    final r2 = await OfflineReconciler(
      db: db, nets: cap,
      onDownload: (id) async {},
      onEvict: (id) async {},
      now: DateTime(2026, 3, 1),
    ).reconcileManga(1);
    expect(r2.toDownload, isEmpty, reason: 'no oscillation on second pass');
  });

  test('RC5: reconcile converges — second pass yields empty toDownload and toEvict', () async {
    // Setup: storage cap of 50 bytes. Seed 6 chapters each 10 bytes = 60 bytes
    // total downloaded, already over cap. Rule is "all" (all desired).
    const cap = SafetyNetConfig(
      timeEvictEnabled: false,
      keepDays: 30,
      storageCapEnabled: true,
      storageCapBytes: 50,
    );

    await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
    await db.setKeepRule(1, OfflineKeepRule.all, 0);

    // Seed 6 chapters as already-downloaded (60 bytes total > 50 cap).
    for (var i = 1; i <= 6; i++) {
      await seedChapter(i, i,
          read: false, serverDl: true,
          dev: OfflineDeviceState.downloaded, bytes: 10,
          downloadedAt: DateTime(2026, 1, i));
    }

    final evicted1 = <int>[];
    final downloaded1 = <int>[];
    await OfflineReconciler(
      db: db, nets: cap,
      onDownload: (id) async => downloaded1.add(id),
      onEvict: (id) async {
        evicted1.add(id);
        await db.setChapterDeviceState(id, OfflineDeviceState.none, bytes: 0);
      },
      now: DateTime(2026, 3, 1),
    ).reconcileManga(1);

    // First pass must evict to bring under cap — don't assert specifics here,
    // just verify something happened (sanity).
    expect(evicted1, isNotEmpty, reason: 'first pass should evict over-cap chapters');

    // Second pass: state is now stable — no new downloads should be emitted
    // because adding any chapter would exceed the cap, and no evictions because
    // we're already at or under it.
    final evicted2 = <int>[];
    final downloaded2 = <int>[];
    final r2 = await OfflineReconciler(
      db: db, nets: cap,
      onDownload: (id) async => downloaded2.add(id),
      onEvict: (id) async => evicted2.add(id),
      now: DateTime(2026, 3, 1),
    ).reconcileManga(1);

    expect(downloaded2, isEmpty, reason: 'second pass must not re-download (fixed point)');
    expect(evicted2, isEmpty, reason: 'second pass must not evict (fixed point)');
    expect(r2.toDownload, isEmpty);
    expect(r2.toEvict, isEmpty);
  });
}
