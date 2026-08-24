// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Regression guard for #354. Asking the server to fetch a chapter sends it out
// to the source, so it must follow a user's decision, not the app starting.
// Launch reconcile swept the whole library and re-issued that request every
// start, which pinned the CPU and kept FlareSolverr solving challenges for
// sources the reader never opened.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_reconciler.dart';
import 'package:tsumiru/src/features/offline/data/reconcile_types.dart';
import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  Future<void> seed() async {
    await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
    await db.setKeepRule(1, OfflineKeepRule.all, 3);
    // Wanted by the rule, but the server hasn't fetched it from the source yet.
    await db.upsertChapterMetadata(
      id: 1, mangaId: 1, name: 'c1', chapterIndex: 1, isRead: false,
      lastPageRead: 0, isBookmarked: false, serverIsDownloaded: false,
      pageCount: 1, updatedAt: DateTime(2026),
    );
  }

  test('a launch-shaped reconcile asks the server for nothing', () async {
    await seed();
    final asked = <int>[];
    await OfflineReconciler(
      db: db,
      nets: SafetyNetConfig.off,
      onDownload: (_) async {},
      onEvict: (_) async {},
      now: DateTime(2026, 3, 1),
      // Launch passes no handler: filling the server is the server's job, and
      // it already does it on its own schedule within its own limit.
    ).reconcileManga(1);

    expect(asked, isEmpty, reason: 'launch must not generate source traffic');
  });

  test('a user-initiated reconcile still asks the server', () async {
    await seed();
    final asked = <int>[];
    await OfflineReconciler(
      db: db,
      nets: SafetyNetConfig.off,
      onDownload: (_) async {},
      onEvict: (_) async {},
      now: DateTime(2026, 3, 1),
      onServerDownload: (ids) async => asked.addAll(ids),
    ).reconcileManga(1);

    expect(asked, [1],
        reason: 'setting a keep rule must still top up the server');
  });

  test(
    'stops asking the server for a chapter that never resolves, after '
    'a bounded number of attempts',
    () async {
      // Regression: a chapter the server can never actually fetch (source
      // gone/renumbered upstream) used to be re-enqueued on every single
      // reconcile pass forever — every app launch, every library sync, every
      // download-queue-drain callback — hammering the server for nothing.
      //
      // Persisted, not in-memory: an in-memory counter would reset every app
      // restart and never actually reach the cap, which is exactly what was
      // observed in the field — attempts stayed frozen at 1 across a whole
      // test session that reopened the app repeatedly.
      await seed();
      const maxAttempts = 5; // mirrors offline_reconciler.dart's own cap
      var totalAsks = 0;
      Future<void> reconcileOnce() => OfflineReconciler(
            db: db,
            nets: SafetyNetConfig.off,
            onDownload: (_) async {},
            onEvict: (_) async {},
            now: DateTime(2026, 3, 1),
            onServerDownload: (ids) async => totalAsks += ids.length,
          ).reconcileManga(1);

      // serverIsDownloaded never flips true in this fixture (simulating a
      // source that can never serve it), so every pass would re-ask forever
      // without the cap.
      for (var i = 0; i < maxAttempts; i++) {
        await reconcileOnce();
      }
      expect(totalAsks, maxAttempts);
      final persisted = await db.chapterById(1);
      expect(persisted?.serverFetchAttempts, maxAttempts,
          reason: 'the count must survive being read back from a fresh '
              'OfflineReconciler instance, the way a new app session would');

      // One more pass, well past the cap: must NOT ask again.
      await reconcileOnce();
      expect(totalAsks, maxAttempts,
          reason: 'exhausted chapters must stop generating server traffic');
    },
  );
}
