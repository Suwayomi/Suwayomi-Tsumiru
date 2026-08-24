// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;

  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  test('opens at schema version 16', () {
    expect(db.schemaVersion, 16);
  });

  test('inserts and reads a manga', () async {
    await db.into(db.offlineMangas).insert(
          OfflineMangasCompanion.insert(
            id: const Value(117),
            title: 'Solo Leveling',
            updatedAt: DateTime.utc(2026),
          ),
        );
    final rows = await db.select(db.offlineMangas).get();
    expect(rows.single.title, 'Solo Leveling');
  });

  test('chapter deviceState defaults to none and round-trips an enum',
      () async {
    await db.into(db.offlineChapters).insert(
          OfflineChaptersCompanion.insert(
            id: const Value(2000),
            mangaId: 552,
            name: 'Chapter 79',
            chapterIndex: 79,
            updatedAt: DateTime.utc(2026),
          ),
        );
    final c = await (db.select(db.offlineChapters)
          ..where((t) => t.id.equals(2000)))
        .getSingle();
    expect(c.deviceState, OfflineDeviceState.none);

    await (db.update(db.offlineChapters)..where((t) => t.id.equals(2000)))
        .write(const OfflineChaptersCompanion(
            deviceState: Value(OfflineDeviceState.downloaded)));
    final c2 = await (db.select(db.offlineChapters)
          ..where((t) => t.id.equals(2000)))
        .getSingle();
    expect(c2.deviceState, OfflineDeviceState.downloaded);
  });

  test('offline page maps (chapterId,pageIndex) -> relative path', () async {
    await db.into(db.offlinePages).insert(
          OfflinePagesCompanion.insert(
            chapterId: 2000,
            pageIndex: 0,
            relativePath: '552/2000/000.jpg',
          ),
        );
    final rows = await (db.select(db.offlinePages)
          ..where((t) => t.chapterId.equals(2000)))
        .get();
    expect(rows.single.relativePath, '552/2000/000.jpg');
  });

  test('clearAll removes the complete offline catalog', () async {
    await db.into(db.offlineMangas).insert(
          OfflineMangasCompanion.insert(
            id: const Value(117),
            title: 'Solo Leveling',
            updatedAt: DateTime.utc(2026),
          ),
        );
    await db.into(db.offlineChapters).insert(
          OfflineChaptersCompanion.insert(
            id: const Value(2000),
            mangaId: 117,
            name: 'Chapter 79',
            chapterIndex: 79,
            updatedAt: DateTime.utc(2026),
          ),
        );
    await db.into(db.offlineCategories).insert(
          const OfflineCategoriesCompanion(
            id: Value(1),
            name: Value('Reading'),
            sortOrder: Value(0),
          ),
        );
    await db.into(db.offlineMangaCategories).insert(
          const OfflineMangaCategoriesCompanion(
            mangaId: Value(117),
            categoryId: Value(1),
          ),
        );
    await db.into(db.offlinePages).insert(
          OfflinePagesCompanion.insert(
            chapterId: 2000,
            pageIndex: 0,
            relativePath: '117/2000/000.jpg',
          ),
        );

    expect(await db.hasCatalogData(), isTrue);
    await db.clearAll();

    expect(await db.hasCatalogData(), isFalse);
    expect(await db.select(db.offlineChapters).get(), isEmpty);
    expect(await db.select(db.offlineCategories).get(), isEmpty);
    expect(await db.select(db.offlineMangaCategories).get(), isEmpty);
    expect(await db.select(db.offlinePages).get(), isEmpty);
  });

  group('categoriesForMangas', () {
    Future<void> seedManga(int id) => db.upsertMangaMetadata(
          id: id,
          title: 'M$id',
          updatedAt: DateTime.utc(2026),
        );

    test('empty input short-circuits to an empty map', () async {
      expect(await db.categoriesForMangas(const {}), isEmpty);
    });

    test('batches every id into one query, keyed by mangaId, ordered by '
        "each category's sortOrder, and omits ids with no categories",
        () async {
      await db.upsertCategory(1, 'Reading', 0, isHidden: false);
      await db.upsertCategory(2, 'Plan to read', 1, isHidden: false);
      await seedManga(10);
      await seedManga(20);
      await seedManga(30); // uncategorized
      await db.replaceMangaCategories(10, [2, 1]); // inserted out of order
      await db.replaceMangaCategories(20, [1]);

      final result = await db.categoriesForMangas({10, 20, 30});

      expect(result[10]!.map((c) => c.id).toList(), [1, 2],
          reason: 'sortOrder governs, not insertion order');
      expect(result[20]!.map((c) => c.id).toList(), [1]);
      expect(result.containsKey(30), isFalse,
          reason: 'no membership rows -> no entry, same as the single-id '
              'form returning an empty list');
    });

    test('matches categoriesForManga(id) for each id in the batch', () async {
      await db.upsertCategory(1, 'Reading', 0, isHidden: false);
      await db.upsertCategory(2, 'Plan to read', 1, isHidden: false);
      await seedManga(10);
      await seedManga(20);
      await db.replaceMangaCategories(10, [1, 2]);
      await db.replaceMangaCategories(20, [2]);

      final batched = await db.categoriesForMangas({10, 20});
      final single10 = await db.categoriesForManga(10);
      final single20 = await db.categoriesForManga(20);

      expect(batched[10]!.map((c) => c.id).toList(),
          single10.map((c) => c.id).toList());
      expect(batched[20]!.map((c) => c.id).toList(),
          single20.map((c) => c.id).toList());
    });
  });

  group('mangaCountByCategory / uncategorizedOf', () {
    Future<void> seedManga(int id) => db.upsertMangaMetadata(
          id: id,
          title: 'M$id',
          updatedAt: DateTime.utc(2026),
        );

    test('mangaCountByCategory: empty input short-circuits to an empty map',
        () async {
      expect(await db.mangaCountByCategory(const {}), isEmpty);
    });

    test('mangaCountByCategory: counts only rows whose mangaId is in the '
        'requested set', () async {
      await db.upsertCategory(1, 'Reading', 0, isHidden: false);
      await seedManga(10);
      await seedManga(20);
      await seedManga(30);
      await db.replaceMangaCategories(10, [1]);
      await db.replaceMangaCategories(20, [1]);
      // Not in the requested set below -- must not inflate category 1's count.
      await db.replaceMangaCategories(30, [1]);

      expect(await db.mangaCountByCategory({10, 20}), {1: 2});
    });

    test('uncategorizedOf: empty input short-circuits to an empty set',
        () async {
      expect(await db.uncategorizedOf(const {}), isEmpty);
    });

    test('uncategorizedOf: only considers requested ids, and a membership '
        'pointing at a never-mirrored category still counts as '
        'uncategorized (mirrors the mapper\'s inner join)', () async {
      await db.upsertCategory(1, 'Reading', 0, isHidden: false);
      await seedManga(10); // categorized
      await seedManga(20); // orphan membership -> counts as uncategorized
      await seedManga(30); // truly uncategorized
      await seedManga(40); // categorized, but NOT in the requested set
      await db.replaceMangaCategories(10, [1]);
      await db.replaceMangaCategories(20, [99]); // 99 was never mirrored
      await db.replaceMangaCategories(40, [1]);

      expect(await db.uncategorizedOf({10, 20, 30}), {20, 30});
    });
  });
}
