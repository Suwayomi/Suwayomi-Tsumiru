// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:drift/native.dart';
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
  test(
    'version 16 categories migrate special identity without guessing auto-add',
    () async {
      final legacy = OfflineDatabase(
        NativeDatabase.memory(
          setup: (db) {
            db.execute(
              'CREATE TABLE offline_categories (id INTEGER PRIMARY KEY, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, is_hidden INTEGER NOT NULL DEFAULT 0)',
            );
            db.execute(
              "INSERT INTO offline_categories (id, name) VALUES (0, 'Default'), (5, 'Other')",
            );
            db.execute('PRAGMA user_version = 16');
          },
        ),
      );
      addTearDown(legacy.close);
      final categories = await legacy.allOfflineCategories();
      expect(
        categories.singleWhere((c) => c.id == 0).isDefaultCategory,
        isTrue,
      );
      expect(
        categories.singleWhere((c) => c.id == 5).isDefaultCategory,
        isFalse,
      );
      expect(categories.every((c) => !c.autoAdd), isTrue);
    },
  );
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

  test(
    'nonzero default identity and auto-add remain independent offline',
    () async {
      final sync = OfflineSync(db);
      await sync.syncCategories([
        cat(81, 'Default').copyWith(defaultCategory: false),
        cat(3, 'Auto add').copyWith(defaultCategory: true),
      ], defaultCategoryId: 81);
      await seedDownloadedManga(10, []);
      final stored = await db.allOfflineCategories();
      expect(stored.singleWhere((c) => c.id == 81).isDefaultCategory, isTrue);
      expect(stored.singleWhere((c) => c.id == 81).autoAdd, isFalse);
      final tabs = await categoriesWithOfflineFallback(
        fetch: () async => throw const SocketException('offline'),
        db: db,
        offlineEnabled: true,
        defaultCategoryId: 81,
      );
      expect(tabs!.map((c) => c.id), isNot(contains(0)));
      expect(tabs.singleWhere((c) => c.id == 81).mangas.totalCount, 1);
      expect(tabs.singleWhere((c) => c.id == 3).defaultCategory, isTrue);
    },
  );

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

    test(
      'a device-local visibility flip yields to the server on re-sync',
      () async {
        final sync = OfflineSync(db);
        await sync.syncCategories([cat(1, 'A', hidden: true)]);

        // Offline unhide: the mirror flips so downloads stay reachable...
        await db.setCategoryHidden(1, false);
        expect((await db.allOfflineCategories()).single.isHidden, isFalse);

        // ...and the server's flag reasserts on the next online sync.
        await sync.syncCategories([cat(1, 'A', hidden: true)]);
        expect((await db.allOfflineCategories()).single.isHidden, isTrue);
      },
    );
  });

  group('categoriesWithOfflineFallback catalog serve', () {
    Future<Never> boom() async => throw const SocketException('unreachable');

    test(
      'serves per-category counts, keeps hidden meta, keeps categories with '
      'nothing downloaded, and homes uncategorized manga in Default',
      () async {
        final sync = OfflineSync(db);
        await sync.syncCategories([
          cat(1, 'Visible', order: 1),
          cat(2, 'Empty', order: 2),
          cat(3, 'Hidden', order: 3, hidden: true),
        ]);
        await seedDownloadedManga(10, [1]);
        await seedDownloadedManga(11, [3]);
        await seedDownloadedManga(12, []); // default category only

        final tabs = await categoriesWithOfflineFallback(
          fetch: boom,
          db: db,
          offlineEnabled: true,
        );

        expect(tabs, isNotNull);
        final byId = {for (final t in tabs!) t.id: t};
        // Default synthesized for the uncategorized download.
        expect(byId[0]?.mangas.totalCount, 1);
        expect(byId[1]?.mangas.totalCount, 1);
        // Nothing downloaded from it, but the category still exists -- dropping
        // it made a user's categories look deleted while offline.
        expect(byId[2]?.mangas.totalCount, 0);
        // Hidden flag survives the round trip into the synthetic DTO.
        expect(byId[3]?.isHidden, isTrue);
      },
    );

    test('orphaned membership rows (category never mirrored or pruned '
        'mid-state) still count their manga into Default', () async {
      final sync = OfflineSync(db);
      await sync.syncCategories([cat(1, 'A')]);
      await seedDownloadedManga(10, [1]);
      // Membership points at a category the mirror has never stored.
      await seedDownloadedManga(11, [99]);

      final tabs = await categoriesWithOfflineFallback(
        fetch: boom,
        db: db,
        offlineEnabled: true,
      );

      final byId = {for (final t in tabs!) t.id: t};
      // The mapper's inner join drops the orphan membership, so the manga
      // renders under Default -- the count must agree.
      expect(byId[0]?.mangas.totalCount, 1);
      expect(byId[1]?.mangas.totalCount, 1);
    });

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
