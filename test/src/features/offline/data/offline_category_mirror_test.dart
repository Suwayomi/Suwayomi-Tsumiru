// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/library/data/category_repository.dart';
import 'package:tsumiru/src/features/library/domain/category/category_model.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_read_fallback.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_sync.dart';
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

  test('pending category edits survive sync and offline reads, and only '
      'unchanged edits clear after a push', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await db.upsertCategory(1, 'Reading', 0, isHidden: false);
    await db.mergePendingCategoryMeta(1, {
      'webUI_sortBy': 'lastRead',
      'webUI_hasUnreadChapters': null,
    });
    await seedDownloadedManga(10, [1]);
    await db.upsertCategory(
      1,
      'Reading',
      0,
      isHidden: false,
      webUiMetaJson:
          '{"webUI_sortBy":"dateAdded","webUI_hasUnreadChapters":"true"}',
    );
    expect((await db.categoryById(1))!.pendingWebUiMetaJson, isNotNull);
    final tabs = await categoriesWithOfflineFallback(
      fetch: boom,
      db: db,
      offlineEnabled: true,
    );
    final meta = {
      for (final m in tabs!.firstWhere((c) => c.id == 1).meta) m.key: m.value,
    };
    expect(meta['webUI_sortBy'], 'lastRead');
    expect(meta.containsKey('webUI_hasUnreadChapters'), isFalse);

    final repository = _PendingMetaRepository();
    final container = ProviderContainer(
      overrides: [
        offlineActiveProvider.overrideWith((ref) => true),
        offlineDatabaseProvider.overrideWithValue(db),
        categoryRepositoryProvider.overrideWithValue(repository),
        authCredentialsStoreProvider.overrideWith(_Credentials.new),
      ],
    );
    addTearDown(container.dispose);
    final push = pushPendingCategoryMeta(container);
    await repository.started.future;
    await db.mergePendingCategoryMeta(1, {'webUI_sortBy': 'unreadChapters'});
    repository.release.complete();
    await push;
    expect(repository.meta['webUI_sortBy'], 'lastRead');
    expect(repository.meta.containsKey('webUI_hasUnreadChapters'), isFalse);
    expect(
      (await db.categoryById(1))!.pendingWebUiMetaJson,
      '{"webUI_sortBy":"unreadChapters"}',
    );
    await pushPendingCategoryMeta(container);
    expect(repository.meta['webUI_sortBy'], 'unreadChapters');
    expect((await db.categoryById(1))!.pendingWebUiMetaJson, isNull);
    expect(
      (await db.categoryById(1))!.webUiMetaJson,
      '{"webUI_sortBy":"unreadChapters"}',
    );
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

class _Credentials extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async =>
      const AuthCredentialsState.empty();
}

class _PendingMetaRepository extends CategoryRepository {
  _PendingMetaRepository()
    : super(
        GraphQLClient(
          link: HttpLink('https://unused.invalid'),
          cache: GraphQLCache(),
        ),
      );

  final started = Completer<void>();
  final release = Completer<void>();
  final meta = <String, String>{'webUI_hasUnreadChapters': 'true'};

  @override
  Future<void> setCategoryMeta({
    required int categoryId,
    required String key,
    required String value,
  }) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    meta[key] = value;
  }

  @override
  Future<void> deleteCategoryMeta({
    required int categoryId,
    required String key,
  }) async {
    meta.remove(key);
  }
}
