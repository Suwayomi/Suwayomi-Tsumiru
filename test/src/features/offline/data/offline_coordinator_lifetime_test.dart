// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Regression guard for the startup UnmountedRefException: the download
// coordinator is a process-wide background worker, so its provider must be
// keep-alive. An auto-dispose coordinator read once (no listeners) is torn
// down at the next async gap, and its persistedPaused callback then dies on a
// dead Ref — which killed launch download-resume and every desktop pump.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_background_downloads.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../../helpers/offline_test_db.dart';

class _FakeStore implements OfflinePageStore {
  @override
  Future<({String relPath, int bytes})> writePage(
          int m, int c, int i, List<int> b, String e) async =>
      (relPath: '$m/$c/$i.$e', bytes: b.length);
  @override
  Future<void> deleteChapter(int m, int c) async {}
  @override
  Future<int> chapterBytes(int m, int c) async => 0;
  @override
  Future<void> clearAll() async {}
  @override
  Future<List<({int pageIndex, String relPath, int bytes})>> transferChapter(
    int fromMangaId,
    int fromChapterId,
    int toMangaId,
    int toChapterId, {
    required bool keepSource,
  }) =>
      throw UnimplementedError();
}

/// Let the auto-dispose scheduler run: an unlistened auto-dispose element is
/// disposed asynchronously, so identity/liveness checks need real event-loop
/// turns between reads.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> makeContainer() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = testOfflineDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      offlineEnabledProvider.overrideWithValue(true),
      offlineActiveProvider.overrideWithValue(true),
      offlineDatabaseProvider.overrideWithValue(db),
      offlinePathsProvider.overrideWithValue(const OfflinePaths('/tmp/x')),
      offlinePageStoreProvider.overrideWithValue(_FakeStore()),
      // A repo with a dummy client: never called here, but building the real
      // one pulls the auth/Hive chain that tests don't have.
      mangaBookRepositoryProvider.overrideWithValue(MangaBookRepository(
        GraphQLClient(
          link: HttpLink('http://127.0.0.1:1'),
          cache: GraphQLCache(),
        ),
      )),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('coordinator survives an async gap after an unlistened read', () async {
    final container = await makeContainer();
    final coord = container.read(offlineDownloadCoordinatorProvider);
    expect(coord, isNotNull);
    await settle();
    // Pre-fix: auto-dispose already unmounted the provider, so isPaused →
    // persistedPaused → ref.read throws UnmountedRefException.
    expect(coord!.isPaused, isFalse);
  });

  test('reads across an async gap return the same coordinator', () async {
    final container = await makeContainer();
    final first = container.read(offlineDownloadCoordinatorProvider);
    await settle();
    final second = container.read(offlineDownloadCoordinatorProvider);
    // One live instance per build generation — otherwise pause/cancel act on
    // a throwaway object instead of the pumping one.
    expect(identical(first, second), isTrue);
  });
}
