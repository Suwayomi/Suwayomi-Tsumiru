// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Regression guard for #413. Asking the server to fetch a chapter sends it out
// to the source, so a single catch-up pass must ask at most once per manga.
// The pass reconciled every touched manga and then ran the awaiting-pull over
// the same set, which asked twice per pass and burned the per-chapter attempt
// budget at double rate.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/updates/updates_filter.dart';
import 'package:tsumiru/src/features/offline/data/offline_chapter_catchup.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

/// Counts how many times the pass pulls a manga's chapter list. Returning null
/// stops the chain before the reconcile machinery, which needs providers this
/// test deliberately leaves unwired.
class _CountingMangaBookRepository extends MangaBookRepository {
  _CountingMangaBookRepository() : super(_dummyClient());

  final calls = <int>[];

  @override
  Future<List<ChapterDto>?> getStoredChapterList(int mangaId) async {
    calls.add(mangaId);
    return null;
  }
}

/// An empty feed, so the watermark scan never sees its boundary and the pass
/// falls back to every keep-rule manga.
class _EmptyUpdatesRepository extends UpdatesRepository {
  _EmptyUpdatesRepository() : super(_dummyClient(), _dummyClient());

  @override
  Future<UpdatesPage?> getRecentChaptersPage({
    int pageNo = 0,
    UpdatesFilter filter = kNoUpdatesFilter,
  }) async => null;
}

void main() {
  setUp(resetChapterCatchUpStateForTest);
  tearDown(resetChapterCatchUpStateForTest);

  test('one catch-up pass pulls a waiting manga once, not twice', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = OfflineDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
    await db.setKeepRule(1, OfflineKeepRule.all, 3);

    final repo = _CountingMangaBookRepository();
    // Already owed a device pull from an earlier pass, so the manga is both
    // feed-touched and awaiting — the shape that produced the double ask.
    seedAwaitingServerDownloadsForTest({1});

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineActiveProvider.overrideWithValue(true),
        offlineDatabaseProvider.overrideWithValue(db),
        mangaBookRepositoryProvider.overrideWithValue(repo),
        updatesRepositoryProvider.overrideWithValue(_EmptyUpdatesRepository()),
        downloadStarterProvider.overrideWithValue(
          ({bool userInitiated = false}) async {},
        ),
      ],
    );
    addTearDown(container.dispose);

    await runKeepRuleCatchUp(container);

    expect(
      repo.calls,
      [1],
      reason:
          'the tail pull must not re-reconcile a manga the pass already '
          'handled — each extra reconcile re-asks the server for every '
          'chapter it does not hold yet',
    );
  });
}
