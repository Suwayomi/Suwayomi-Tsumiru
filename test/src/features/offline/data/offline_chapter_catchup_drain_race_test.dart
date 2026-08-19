// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:drift/native.dart';
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

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

GraphQLClient _dummyClient() => GraphQLClient(
      link: HttpLink('http://localhost:0'),
      cache: GraphQLCache(),
    );

/// Reports "no stored chapters" for every manga, which makes `_syncAndReconcile`
/// mark the manga unsynced (so `_pullAwaiting` re-queues it) without touching
/// any of the reconcile machinery (db/manager/coordinator providers). The
/// first call pauses on [gate] so a test can land a concurrent drain event
/// while the pass is mid-flight; later calls return immediately.
class _PausingMangaBookRepository extends MangaBookRepository {
  _PausingMangaBookRepository() : super(_dummyClient());

  final Completer<void> gate = Completer<void>();
  int callCount = 0;

  @override
  Future<List<ChapterDto>?> getStoredChapterList(int mangaId) async {
    callCount++;
    if (callCount == 1) await gate.future;
    return null;
  }
}

/// Same contract as above, but never pauses — used where the pause needs to
/// happen earlier in the call chain (the database read).
class _CountingMangaBookRepository extends MangaBookRepository {
  _CountingMangaBookRepository() : super(_dummyClient());

  int callCount = 0;

  @override
  Future<List<ChapterDto>?> getStoredChapterList(int mangaId) async {
    callCount++;
    return null;
  }
}

/// An empty in-memory [OfflineDatabase] whose `libraryManga()` pauses on
/// [gate] before delegating to the real (empty) query — lets a test land a
/// concurrent drain event while `runKeepRuleCatchUp` is between setting
/// `_running = true` and reaching the `keepRuleManga.isEmpty` check.
class _PausingEmptyOfflineDatabase extends OfflineDatabase {
  _PausingEmptyOfflineDatabase() : super(NativeDatabase.memory());

  final Completer<void> gate = Completer<void>();

  @override
  Future<List<OfflineManga>> libraryManga() async {
    await gate.future;
    return super.libraryManga();
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(resetChapterCatchUpStateForTest);
  tearDown(resetChapterCatchUpStateForTest);

  group('pullAfterServerDownloads', () {
    test(
        'a drain event landing mid-pass is replayed, not stranded '
        '(regression: bug 1)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = _PausingMangaBookRepository();
      var startCalls = 0;

      seedAwaitingServerDownloadsForTest({1});

      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineActiveProvider.overrideWithValue(true),
        mangaBookRepositoryProvider.overrideWithValue(repo),
        downloadStarterProvider.overrideWithValue(({bool userInitiated = false}) async {
          startCalls++;
        }),
      ]);
      addTearDown(container.dispose);

      // Runs synchronously up to the paused await inside getStoredChapterList.
      final passFuture = pullAfterServerDownloads(container);

      // A queue-drain event lands while the pass is still in flight.
      simulateQueueDrainForTest(container);

      repo.gate.complete();
      await passFuture;

      expect(repo.callCount, 2,
          reason: 'the deferred drain must trigger a second _pullAwaiting '
              'pass so manga 1 (re-queued by the first, failed attempt) '
              'gets retried instead of stranded');
      expect(startCalls, 2,
          reason: 'each _pullAwaiting pass that processes an obligation '
              'kicks the download starter');
    });

    test('no concurrent drain event → only a single pass runs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = _CountingMangaBookRepository();
      var startCalls = 0;

      seedAwaitingServerDownloadsForTest({1});

      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineActiveProvider.overrideWithValue(true),
        mangaBookRepositoryProvider.overrideWithValue(repo),
        downloadStarterProvider.overrideWithValue(({bool userInitiated = false}) async {
          startCalls++;
        }),
      ]);
      addTearDown(container.dispose);

      await pullAfterServerDownloads(container);

      expect(repo.callCount, 1,
          reason: 'without a concurrent drain event there is nothing to '
              'replay');
      expect(startCalls, 1);
    });
  });

  group('runKeepRuleCatchUp — empty keep-rule set', () {
    test(
        'a drain event landing while the keep-rule set is empty is still '
        'replayed (regression: bug 2)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = _PausingEmptyOfflineDatabase();
      addTearDown(db.close);
      final repo = _CountingMangaBookRepository();
      var startCalls = 0;

      seedAwaitingServerDownloadsForTest({1});

      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineActiveProvider.overrideWithValue(true),
        offlineDatabaseProvider.overrideWithValue(db),
        mangaBookRepositoryProvider.overrideWithValue(repo),
        downloadStarterProvider.overrideWithValue(({bool userInitiated = false}) async {
          startCalls++;
        }),
      ]);
      addTearDown(container.dispose);

      // Runs synchronously up to the paused await inside libraryManga(). At
      // this point `_running` is already true but the pass has not yet
      // reached the `keepRuleManga.isEmpty` early return.
      final passFuture = runKeepRuleCatchUp(container);

      simulateQueueDrainForTest(container);

      db.gate.complete();
      await passFuture;

      expect(repo.callCount, 1,
          reason: 'the empty-keep-rule early return must still drain the '
              'deferred pull instead of leaving it stranded until the next '
              'pass');
      expect(startCalls, 1);
    });

    test('no concurrent drain event → empty keep-rule set is a pure no-op',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = _PausingEmptyOfflineDatabase();
      addTearDown(db.close);
      db.gate.complete(); // don't pause — nothing to race against here
      final repo = _CountingMangaBookRepository();
      var startCalls = 0;

      seedAwaitingServerDownloadsForTest({1});

      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineActiveProvider.overrideWithValue(true),
        offlineDatabaseProvider.overrideWithValue(db),
        mangaBookRepositoryProvider.overrideWithValue(repo),
        downloadStarterProvider.overrideWithValue(({bool userInitiated = false}) async {
          startCalls++;
        }),
      ]);
      addTearDown(container.dispose);

      await runKeepRuleCatchUp(container);

      expect(repo.callCount, 0,
          reason: 'without a drain event, the empty-keep-rule path must not '
              'touch _awaitingServerDownloads at all');
      expect(startCalls, 0);
    });
  });
}
