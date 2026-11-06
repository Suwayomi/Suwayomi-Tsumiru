// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/library/data/category_repository.dart';
import 'package:tsumiru/src/features/library/data/default_category.dart';
import 'package:tsumiru/src/features/library/domain/category/category_model.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_read_fallback.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_sync.dart';
import 'package:tsumiru/src/features/offline/data/server_reachability.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

import '../../../../helpers/offline_test_db.dart';

CategoryDto cat(int id, String name, {int order = 0, bool hidden = false}) =>
    Fragment$CategoryDto(
      defaultCategory: id == 0,
      id: id,
      includeInDownload: Enum$IncludeOrExclude.UNSET,
      includeInUpdate: Enum$IncludeOrExclude.UNSET,
      name: name,
      order: order,
      mangas: Fragment$CategoryDto$mangas(totalCount: 0),
      meta: [
        if (hidden)
          Fragment$CategoryDto$meta(key: kCategoryHiddenMetaKey, value: 'true'),
      ],
    );

class _Categories extends Fake implements CategoryRepository {
  int fetches = 0;

  @override
  Future<List<CategoryDto>?> getCategoryList() async {
    fetches++;
    return [cat(1, 'A')];
  }
}

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  Future<void> seedDownloadedManga(int mangaId, List<int> categories) async {
    await db.upsertMangaMetadata(
      id: mangaId,
      title: 'M$mangaId',
      updatedAt: DateTime(2026),
    );
    await db.replaceMangaCategories(mangaId, categories);
    await db.upsertChapterMetadata(
      id: 100 + mangaId,
      mangaId: mangaId,
      name: 'c',
      chapterIndex: 1,
      isRead: false,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: true,
      pageCount: 1,
      updatedAt: DateTime(2026),
    );
    await db.setChapterDeviceState(
      100 + mangaId,
      OfflineDeviceState.downloaded,
      bytes: 1,
    );
  }

  Future<Never> boom() async => throw const SocketException('unreachable');

  test('mirrors fetched categories when sync becomes available', () async {
    await OfflineSync(db).syncCategories([cat(1, 'A', hidden: true)]);
    final repository = _Categories();
    OfflineSync? availableSync;
    final container = ProviderContainer(
      overrides: [
        offlineReadDatabaseProvider.overrideWithValue(db),
        viewOfflineNowProvider.overrideWithValue(false),
        serverUnreachableProvider.overrideWithValue(false),
        categoryRepositoryProvider.overrideWithValue(repository),
        defaultCategoryIdProvider.overrideWith((ref) async => 0),
        offlineSyncProvider.overrideWith((ref) => availableSync),
      ],
    );
    addTearDown(container.dispose);
    final updates = <AsyncValue<List<CategoryDto>?>>[];
    container.listen(categoryControllerProvider, (_, next) => updates.add(next));
    final categories = await container.read(categoryControllerProvider.future);
    expect(categories!.single.isHidden, isFalse);
    expect((await db.allOfflineCategories()).single.isHidden, isTrue);
    updates.clear();

    final mirrored = Completer<void>();
    availableSync = OfflineSync(db, onSynced: () async => mirrored.complete());
    container.invalidate(offlineSyncProvider);
    await mirrored.future.timeout(const Duration(seconds: 5));

    expect((await db.allOfflineCategories()).single.isHidden, isFalse);
    expect(repository.fetches, 1);
    expect(updates, isEmpty);
    expect(container.read(categoryControllerProvider).value, same(categories));
  });

  test('syncs prune, keep the mirror on an empty list, mirror hidden and '
      'serve offline', () async {
    final sync = OfflineSync(db);
    await sync.syncCategories([cat(1, 'A'), cat(2, 'Doomed')]);
    await seedDownloadedManga(10, [1]);
    await seedDownloadedManga(11, [2]);

    await sync.syncCategories([cat(1, 'A', hidden: true)]);
    expect((await db.allOfflineCategories()).map((c) => c.id), [1]);
    expect((await db.allOfflineCategories()).single.isHidden, isTrue);
    expect(await db.categoriesForManga(11), isEmpty);

    await sync.syncCategories(const []);
    expect((await db.allOfflineCategories()).length, 1);

    await sync.syncCategories([cat(1, 'A')]);
    expect((await db.allOfflineCategories()).single.isHidden, isFalse);

    final tabs = await categoriesWithOfflineFallback(
      fetch: boom,
      db: db,
      offlineEnabled: true,
    );
    expect(tabs!.map((t) => t.id), isNot(contains(2)));
    expect(tabs.firstWhere((t) => t.id == 0).mangas.totalCount, 1);
  });
}
