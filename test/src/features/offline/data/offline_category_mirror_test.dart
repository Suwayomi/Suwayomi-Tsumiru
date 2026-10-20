// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/domain/category/category_model.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_read_fallback.dart';
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

  group('syncCategories', () {
    test('prunes categories the server no longer has', () async {
      final sync = OfflineSync(db);
      await sync.syncCategories([cat(1, 'A'), cat(2, 'B')]);
      await seedDownloadedManga(10, [2]);

      await sync.syncCategories([cat(1, 'A')]);

      final stored = await db.allOfflineCategories();
      expect(stored.map((c) => c.id), [1]);
      // Membership rows of the pruned category go with it.
      expect(await db.categoriesForManga(10), isEmpty);
    });

    test('an empty server list never wipes the mirror', () async {
      final sync = OfflineSync(db);
      await sync.syncCategories([cat(1, 'A')]);

      await sync.syncCategories(const []);

      expect((await db.allOfflineCategories()).length, 1);
    });

    test('mirrors the hidden flag both ways', () async {
      final sync = OfflineSync(db);
      await sync.syncCategories([cat(1, 'A', hidden: true)]);
      expect((await db.allOfflineCategories()).single.isHidden, isTrue);

      await sync.syncCategories([cat(1, 'A')]);
      expect((await db.allOfflineCategories()).single.isHidden, isFalse);
    });
  });

  group('categoriesWithOfflineFallback catalog serve', () {
    Future<Never> boom() async => throw const SocketException('unreachable');

    test('deleted category stops appearing offline after a re-sync', () async {
      final sync = OfflineSync(db);
      await sync.syncCategories([cat(1, 'A'), cat(2, 'Doomed')]);
      await seedDownloadedManga(10, [1]);
      await seedDownloadedManga(11, [2]);

      // Server deleted category 2; next online category load re-syncs.
      await sync.syncCategories([cat(1, 'A')]);

      final tabs = await categoriesWithOfflineFallback(
        fetch: boom,
        db: db,
        offlineEnabled: true,
      );
      expect(tabs!.map((t) => t.id), isNot(contains(2)));
      // Its manga did not vanish -- it re-homes into Default.
      expect(tabs.firstWhere((t) => t.id == 0).mangas.totalCount, 1);
    });
  });
}
