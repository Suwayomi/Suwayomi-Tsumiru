// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/data/category_repository.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import '../../../helpers/offline_test_db.dart';

MangaDto _manga(int id, String title) => Fragment$MangaDto(
      id: id,
      title: title,
      bookmarkCount: 0,
      chapters: Fragment$MangaDto$chapters(totalCount: 0),
      downloadCount: 0,
      genre: const [],
      inLibrary: true,
      inLibraryAt: '0',
      initialized: true,
      meta: const [],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords:
          Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
      unreadCount: 0,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/$id',
    );

/// Returns a per-server library keyed off the active server URL, or throws when
/// that server is "unreachable".
class _PerServerRepo implements CategoryRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw const SocketException('offline');
}

class _Repo extends _PerServerRepo {
  _Repo(this.mangas, {this.throws = false});
  final List<MangaDto> mangas;
  final bool throws;
  @override
  Future<List<MangaDto>?> getAllLibraryMangas() async {
    if (throws) throw const SocketException('server unreachable');
    return mangas;
  }
}

CategoryRepository _repoFor(String? url) {
  switch (url) {
    case 'http://B':
      return _Repo([_manga(100, 'ServerB')]);
    case 'http://B-down':
      return _Repo(const [], throws: true);
    default:
      return _Repo([_manga(1, 'ServerA')]);
  }
}

void main() {
  test('online: switching servers shows the new server immediately', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      offlineEnabledProvider.overrideWithValue(false),
      categoryRepositoryProvider
          .overrideWith((ref) => _repoFor(ref.watch(serverUrlProvider))),
    ]);
    addTearDown(c.dispose);
    c.listen(libraryMangaListProvider, (_, __) {}, fireImmediately: true);

    c.read(serverUrlProvider.notifier).update('http://A');
    await Future<void>.delayed(Duration.zero);
    expect((await c.read(libraryMangaListProvider.future))!.map((m) => m.id),
        [1]);

    c.read(serverUrlProvider.notifier).update('http://B');
    await Future<void>.delayed(Duration.zero);
    expect((await c.read(libraryMangaListProvider.future))!.map((m) => m.id),
        [100]);
  });

  test('#145: a momentarily-unreachable new server does not show the old '
      "server's offline library", () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = testOfflineDatabase();
    addTearDown(db.close);
    // The offline catalog holds server A's downloaded entry.
    await db.upsertMangaMetadata(
        id: 1, title: 'ServerA-cached', updatedAt: DateTime(2026));

    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      offlineDatabaseProvider.overrideWithValue(db),
      offlineEnabledProvider.overrideWithValue(true),
      offlineSyncProvider.overrideWithValue(null),
      categoryRepositoryProvider
          .overrideWith((ref) => _repoFor(ref.watch(serverUrlProvider))),
    ]);
    addTearDown(c.dispose);
    c.listen(libraryMangaListProvider, (_, __) {}, fireImmediately: true);

    // Load on A: succeeds, stamps the catalog origin as A.
    c.read(serverUrlProvider.notifier).update('http://A');
    await Future<void>.delayed(Duration.zero);
    expect((await c.read(libraryMangaListProvider.future))!.map((m) => m.id),
        [1]);

    // Switch to B while it's unreachable: the A catalog must NOT be served, so
    // the library surfaces the error instead of A's stale downloaded rows.
    c.read(serverUrlProvider.notifier).update('http://B-down');
    await Future<void>.delayed(Duration.zero);
    await expectLater(c.read(libraryMangaListProvider.future),
        throwsA(isA<SocketException>()));
  });

  test('cold start with unknown catalog origin still serves offline data',
      () async {
    // Offline on, catalog holds an entry, origin never stamped (fresh install /
    // cold start), and the server is unreachable from the start. The fallback
    // must still serve — a null origin is not evidence of a different server.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = testOfflineDatabase();
    addTearDown(db.close);
    await db.upsertMangaMetadata(
        id: 1, title: 'cached', updatedAt: DateTime(2026));

    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      offlineDatabaseProvider.overrideWithValue(db),
      offlineEnabledProvider.overrideWithValue(true),
      offlineSyncProvider.overrideWithValue(null),
      categoryRepositoryProvider
          .overrideWith((ref) => _Repo(const [], throws: true)),
    ]);
    addTearDown(c.dispose);
    c.listen(libraryMangaListProvider, (_, __) {}, fireImmediately: true);

    expect((await c.read(libraryMangaListProvider.future))!.map((m) => m.id),
        [1]);
  });

  test('offline: a reachable new server replaces the old catalog, no leak',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = testOfflineDatabase();
    addTearDown(db.close);
    await db.upsertMangaMetadata(
        id: 1, title: 'ServerA-cached', updatedAt: DateTime(2026));

    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      offlineDatabaseProvider.overrideWithValue(db),
      offlineEnabledProvider.overrideWithValue(true),
      offlineSyncProvider.overrideWithValue(null),
      categoryRepositoryProvider
          .overrideWith((ref) => _repoFor(ref.watch(serverUrlProvider))),
    ]);
    addTearDown(c.dispose);
    c.listen(libraryMangaListProvider, (_, __) {}, fireImmediately: true);

    c.read(serverUrlProvider.notifier).update('http://A');
    await Future<void>.delayed(Duration.zero);
    await c.read(libraryMangaListProvider.future);

    c.read(serverUrlProvider.notifier).update('http://B');
    await Future<void>.delayed(Duration.zero);
    // B is reachable: shows B's library, never A's cached id 1.
    expect((await c.read(libraryMangaListProvider.future))!.map((m) => m.id),
        [100]);
  });
}
