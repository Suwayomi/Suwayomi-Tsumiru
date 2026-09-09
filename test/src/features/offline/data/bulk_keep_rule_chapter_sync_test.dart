// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Tests for the fix that ensures bulk keep-rule changes also trigger chapter
// syncs for manga whose chapter list has never been loaded into the local DB.
//
// Root cause of the original bug: for manga never opened in manga details,
// offlineChapters has no rows. reconcileMangaCore sees an empty chapter list,
// desiredChapterIds returns {}, and silently does nothing — no server enqueue,
// no device download. syncAndReconcileMangaSet is the fix: it runs the full
// fetch→sync→reconcile chain for exactly these manga.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_chapter_catchup.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../../helpers/offline_test_db.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

GraphQLClient _dummyClient() => GraphQLClient(
      link: HttpLink('http://localhost:0'),
      cache: GraphQLCache(),
    );

/// Always returns null (simulates network failure / server has no chapters).
class _NullChapterRepo extends MangaBookRepository {
  _NullChapterRepo() : super(_dummyClient());

  final List<int> calledFor = [];

  @override
  Future<List<ChapterDto>?> getStoredChapterList(int mangaId) async {
    calledFor.add(mangaId);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(resetChapterCatchUpStateForTest);
  tearDown(resetChapterCatchUpStateForTest);

  // --- Original bug: empty offlineChapters silently breaks reconcile ----------

  group('original bug — empty offlineChapters causes silent no-op', () {
    test(
      'chaptersForManga returns empty when syncChapters was never called',
      () async {
        // This documents the precondition that triggers the bug.
        // When a manga has a keep rule but its chapters were never fetched
        // (e.g. the user never opened the manga details screen), the local DB
        // has an offlineMangas row but no offlineChapters rows.
        // reconcileMangaCore then calls chaptersForManga → [], produces
        // desiredChapterIds([], rule, count) = {}, and silently does nothing.
        final db = testOfflineDatabase();
        addTearDown(db.close);

        await db.upsertMangaMetadata(
          id: 1,
          title: 'Manga A',
          updatedAt: DateTime(2026),
        );
        await db.setKeepRule(1, OfflineKeepRule.nUnread, 5);

        final chapters = await db.chaptersForManga(1);
        expect(
          chapters,
          isEmpty,
          reason: 'chapters have never been synced; the reconciler would '
              'see an empty list and queue nothing',
        );
      },
    );

    test(
      'setKeepRule silently no-ops when the manga has no offlineMangas row',
      () async {
        // Root cause of failure mode #3 ("nothing happens, not even the keep
        // rule change"). setKeepRule is a pure UPDATE, so with no row it
        // touches zero rows and the rule never persists. The bulk handler must
        // mirror the manga row (from the DTO it holds) before calling this.
        final db = testOfflineDatabase();
        addTearDown(db.close);

        // No upsertMangaMetadata — the row is deliberately absent.
        await db.setKeepRule(42, OfflineKeepRule.all, 3);

        final row = await (db.select(db.offlineMangas)
              ..where((t) => t.id.equals(42)))
            .getSingleOrNull();
        expect(
          row,
          isNull,
          reason: 'setKeepRule is an UPDATE, not an upsert — it cannot create '
              'the row, so the keep rule is lost with no error raised',
        );

        // After the row exists, the same call persists.
        await db.upsertMangaMetadata(
          id: 42,
          title: 'Manga B',
          updatedAt: DateTime(2026),
        );
        await db.setKeepRule(42, OfflineKeepRule.all, 3);
        final after = await (db.select(db.offlineMangas)
              ..where((t) => t.id.equals(42)))
            .getSingle();
        expect(after.keepRule, OfflineKeepRule.all);
        expect(after.keepUnreadCount, 3);
      },
    );
  });

  // --- syncAndReconcileMangaSet guards -----------------------------------------

  group('syncAndReconcileMangaSet — guards', () {
    test('empty set is a no-op — repo and starter are never called', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = testOfflineDatabase();
      addTearDown(db.close);
      final repo = _NullChapterRepo();
      final starterCalls = <bool>[];

      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineActiveProvider.overrideWithValue(true),
        offlineDatabaseProvider.overrideWithValue(db),
        mangaBookRepositoryProvider.overrideWithValue(repo),
        downloadStarterProvider.overrideWithValue(
          ({bool userInitiated = false}) async => starterCalls.add(userInitiated),
        ),
      ]);
      addTearDown(container.dispose);

      await syncAndReconcileMangaSet(container, {});

      expect(
        repo.calledFor,
        isEmpty,
        reason: 'an empty set must skip the fetch loop entirely',
      );
      expect(
        starterCalls,
        isEmpty,
        reason: 'no point starting downloads when there is nothing to sync',
      );
    });

    test(
      'offline inactive → no-op even when manga IDs are provided',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final db = testOfflineDatabase();
        addTearDown(db.close);
        final repo = _NullChapterRepo();
        final starterCalls = <bool>[];

        final container = ProviderContainer(overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          offlineActiveProvider.overrideWithValue(false),
          offlineDatabaseProvider.overrideWithValue(db),
          mangaBookRepositoryProvider.overrideWithValue(repo),
          downloadStarterProvider.overrideWithValue(
            ({bool userInitiated = false}) async =>
                starterCalls.add(userInitiated),
          ),
        ]);
        addTearDown(container.dispose);

        await syncAndReconcileMangaSet(container, {1, 2});

        expect(
          repo.calledFor,
          isEmpty,
          reason: 'offline inactive means no catalog is available; no '
              'sync or download should start',
        );
        expect(starterCalls, isEmpty);
      },
    );
  });

  // --- syncAndReconcileMangaSet integration ------------------------------------

  group('syncAndReconcileMangaSet — chapter fetch and download start', () {
    test(
      'calls getStoredChapterList for each manga, then kicks the download starter',
      () async {
        // This is the happy path of the fix: manga IDs provided, offline
        // active, chapters fetched (even null = network error) for each,
        // then download starter called once at the end.
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final db = testOfflineDatabase();
        addTearDown(db.close);
        final repo = _NullChapterRepo();
        final starterCalls = <bool>[];

        final container = ProviderContainer(overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          offlineActiveProvider.overrideWithValue(true),
          offlineDatabaseProvider.overrideWithValue(db),
          mangaBookRepositoryProvider.overrideWithValue(repo),
          downloadStarterProvider.overrideWithValue(
            ({bool userInitiated = false}) async =>
                starterCalls.add(userInitiated),
          ),
        ]);
        addTearDown(container.dispose);

        await syncAndReconcileMangaSet(container, {1, 2});

        expect(
          repo.calledFor.toSet(),
          {1, 2},
          reason: 'the chapter list must be fetched from the server for '
              'every manga in the set, not just the first',
        );
        expect(
          starterCalls.length,
          1,
          reason: 'the download starter is kicked exactly once at the end '
              'of the full sync so freshly-queued chapters begin transferring',
        );
      },
    );

    test(
      'fetch failure for every manga still calls the download starter once',
      () async {
        // Even when all fetches fail (network error, server unreachable),
        // the starter fires so any pre-existing queued work can still make
        // progress. This mirrors runKeepRuleCatchUp's own behaviour.
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final db = testOfflineDatabase();
        addTearDown(db.close);
        final repo = _NullChapterRepo();
        final starterCalls = <bool>[];

        final container = ProviderContainer(overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          offlineActiveProvider.overrideWithValue(true),
          offlineDatabaseProvider.overrideWithValue(db),
          mangaBookRepositoryProvider.overrideWithValue(repo),
          downloadStarterProvider.overrideWithValue(
            ({bool userInitiated = false}) async =>
                starterCalls.add(userInitiated),
          ),
        ]);
        addTearDown(container.dispose);

        await syncAndReconcileMangaSet(container, {1, 2, 3});

        expect(
          repo.calledFor.toSet(),
          {1, 2, 3},
          reason: 'all manga are attempted even when every fetch returns null',
        );
        expect(
          starterCalls,
          [false],
          reason: 'the starter fires once regardless of individual sync '
              'failures — the same pattern as runKeepRuleCatchUp',
        );
      },
    );

    test(
      'userInitiated is passed through to the download starter',
      () async {
        // The bulk keep-rule change is an explicit user gesture, so the FGS
        // must start in user-initiated mode (drives the "X/Y" notification).
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final db = testOfflineDatabase();
        addTearDown(db.close);
        final repo = _NullChapterRepo();
        final starterCalls = <bool>[];

        final container = ProviderContainer(overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          offlineActiveProvider.overrideWithValue(true),
          offlineDatabaseProvider.overrideWithValue(db),
          mangaBookRepositoryProvider.overrideWithValue(repo),
          downloadStarterProvider.overrideWithValue(
            ({bool userInitiated = false}) async =>
                starterCalls.add(userInitiated),
          ),
        ]);
        addTearDown(container.dispose);

        await syncAndReconcileMangaSet(container, {1}, userInitiated: true);

        expect(
          starterCalls,
          [true],
          reason: 'a user-initiated bulk keep must start the FGS in '
              'user-initiated mode, not the background default',
        );
      },
    );
  });
}
