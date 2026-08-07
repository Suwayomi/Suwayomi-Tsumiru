// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  Future<void> seedManga(int id, String title) =>
      db.upsertMangaMetadata(id: id, title: title, updatedAt: DateTime(2026));

  Future<void> seedChapter(int id, int mangaId) => db.upsertChapterMetadata(
        id: id,
        mangaId: mangaId,
        name: 'c$id',
        chapterIndex: id,
        isRead: false,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: 1,
        updatedAt: DateTime(2026),
      );

  test('lists series with files OR a rule (union); excludes neither', () async {
    // m1: keep all + 2 downloaded (100B each) + 1 queued.
    await seedManga(1, 'Alpha');
    await db.setKeepRule(1, OfflineKeepRule.all, 3);
    for (final c in [10, 11]) {
      await seedChapter(c, 1);
      await db.setChapterDeviceState(c, OfflineDeviceState.downloaded,
          bytes: 100, downloadedAt: DateTime(2026));
    }
    await seedChapter(12, 1);
    await db.setChapterDeviceState(12, OfflineDeviceState.queued);

    // m2: a rule, NOTHING downloaded yet (must still appear).
    await seedManga(2, 'Beta');
    await db.setKeepRule(2, OfflineKeepRule.nUnread, 5);

    // m3: files but NO rule (hand-saved) — must appear too.
    await seedManga(3, 'Gamma');
    await seedChapter(30, 3);
    await db.setChapterDeviceState(30, OfflineDeviceState.downloaded,
        bytes: 50, downloadedAt: DateTime(2026));

    // m4: no rule, no files — must NOT appear.
    await seedManga(4, 'Delta');

    final rows = await db.watchOfflineSeries().first;
    final byId = {for (final s in rows) s.manga.id: s};

    expect(byId.keys.toSet(), {1, 2, 3}); // m4 excluded

    expect(byId[1]!.manga.keepRule, OfflineKeepRule.all);
    expect(byId[1]!.downloaded, 2);
    expect(byId[1]!.inFlight, 1);
    expect(byId[1]!.bytes, 200);

    // Rule with nothing downloaded — surfaced with zeroed aggregates.
    expect(byId[2]!.manga.keepRule, OfflineKeepRule.nUnread);
    expect(byId[2]!.downloaded, 0);

    // Files with no rule — surfaced as Manual (keepRule off).
    expect(byId[3]!.manga.keepRule, OfflineKeepRule.off);
    expect(byId[3]!.downloaded, 1);
    expect(byId[3]!.bytes, 50);
  });

  test('detach basis: pinned downloaded survive a rule→off; series still listed',
      () async {
    // Mirrors detachKeepRule at the DB level: pin downloaded, clear the rule.
    // The reconciler protects pinned chapters (tested in reconcile_eviction);
    // here we assert the catalog state detach leaves behind.
    await seedManga(1, 'Alpha');
    await db.setKeepRule(1, OfflineKeepRule.all, 3);
    await seedChapter(10, 1);
    await db.setChapterDeviceState(10, OfflineDeviceState.downloaded,
        bytes: 100, downloadedAt: DateTime(2026));
    await seedChapter(11, 1);
    await db.setChapterDeviceState(11, OfflineDeviceState.queued);

    await db.setChapterPinned(10, true);
    await db.setKeepRule(1, OfflineKeepRule.off, 3);

    final downloaded = await db.downloadedChaptersForManga(1);
    expect(downloaded.single.id, 10);
    expect(downloaded.single.pinned, true); // protected from eviction

    // Still listed (it has files), now as Manual (rule off).
    final rows = await db.watchOfflineSeries().first;
    final row = rows.firstWhere((s) => s.manga.id == 1);
    expect(row.manga.keepRule, OfflineKeepRule.off);
    expect(row.downloaded, 1);
  });
}
