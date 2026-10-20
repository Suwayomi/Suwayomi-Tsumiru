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

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_chapter_catchup.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../../helpers/offline_test_db.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('bulk-keep-rule-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tmp.path,
        );
  });

  setUp(resetChapterCatchUpStateForTest);
  tearDown(resetChapterCatchUpStateForTest);

  // --- Original bug: empty offlineChapters silently breaks reconcile ----------

  group('original bug — empty offlineChapters causes silent no-op', () {});

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

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            offlineActiveProvider.overrideWithValue(true),
            offlineDatabaseProvider.overrideWithValue(db),
            mangaBookRepositoryProvider.overrideWithValue(repo),
            downloadStarterProvider.overrideWithValue(
              ({bool userInitiated = false}) async =>
                  starterCalls.add(userInitiated),
            ),
          ],
        );
        addTearDown(container.dispose);

        await syncAndReconcileMangaSet(container, {1, 2});

        expect(
          repo.calledFor.toSet(),
          {1, 2},
          reason:
              'the chapter list must be fetched from the server for '
              'every manga in the set, not just the first',
        );
        expect(
          starterCalls.length,
          1,
          reason:
              'the download starter is kicked exactly once at the end '
              'of the full sync so freshly-queued chapters begin transferring',
        );
      },
    );
  });
}
