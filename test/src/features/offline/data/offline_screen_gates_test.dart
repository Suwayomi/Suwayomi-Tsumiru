// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/data/category_repository.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_dto_mappers.dart';
import 'package:tsumiru/src/features/offline/data/offline_read_fallback.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../../helpers/offline_test_db.dart';

class _ThrowingCategoryRepo implements CategoryRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw Exception('offline');
}

class _ThrowingMangaBookRepo implements MangaBookRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw Exception('offline');
}

Future<ProviderContainer> _container(
    OfflineDatabase db, List<Override> extra) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    offlineDatabaseProvider.overrideWithValue(db),
    offlineEnabledProvider.overrideWithValue(true),
    ...extra,
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  group('offlineDefaultCategoryDto', () {
    test('carries the manga count so it survives the nonZero filter', () {
      final cat = offlineDefaultCategoryDto(42);
      expect(cat.id, 0);
      expect(cat.mangas.totalCount, 42);
      expect(cat.defaultCategory, true);
    });
  });

  group('categoriesWithOfflineFallback', () {
    Future<Never> boom() async => throw Exception('server down');

    test('returns a single default category (count) when fetch throws', () async {
      await db.upsertMangaMetadata(id: 1, title: 'A', updatedAt: DateTime(2026));
      await db.upsertMangaMetadata(id: 2, title: 'B', updatedAt: DateTime(2026));
      final cats = await categoriesWithOfflineFallback(
          fetch: boom, db: db, offlineEnabled: true);
      expect(cats!.length, 1);
      expect(cats.single.mangas.totalCount, 2);
    });

    test('rethrows when the catalog is empty', () async {
      expect(categoriesWithOfflineFallback(fetch: boom, db: db, offlineEnabled: true),
          throwsException);
    });

    test('rethrows when offline disabled', () async {
      await db.upsertMangaMetadata(id: 1, title: 'A', updatedAt: DateTime(2026));
      expect(categoriesWithOfflineFallback(fetch: boom, db: db, offlineEnabled: false),
          throwsException);
    });
  });

  group('chapterMetaWithOfflineFallback', () {
    Future<Never> boom() async => throw Exception('server down');

    test('falls back to the catalog chapter row on throw', () async {
      await db.upsertChapterMetadata(
          id: 99, mangaId: 1, name: 'Ch99', chapterIndex: 5, isRead: false,
          lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
          pageCount: 10, updatedAt: DateTime(2026));
      final ch = await chapterMetaWithOfflineFallback(
          fetch: boom, db: db, offlineEnabled: true, chapterId: 99);
      expect(ch!.id, 99);
      expect(ch.name, 'Ch99');
    });

    test('rethrows when the chapter is not in the catalog', () async {
      expect(
          chapterMetaWithOfflineFallback(
              fetch: boom, db: db, offlineEnabled: true, chapterId: 404),
          throwsException);
    });
  });

  // The bugs Aaron actually hit: the real gating providers must render offline,
  // not just the helpers in isolation.
  group('real gating providers offline', () {
    test('CategoryController returns a default category when the server fails',
        () async {
      await db.upsertMangaMetadata(id: 1, title: 'A', updatedAt: DateTime(2026));
      await db.upsertMangaMetadata(id: 2, title: 'B', updatedAt: DateTime(2026));
      final c = await _container(db, [
        categoryRepositoryProvider.overrideWithValue(_ThrowingCategoryRepo()),
      ]);
      final cats = await c.read(categoryControllerProvider.future);
      expect(cats!.length, 1);
      expect(cats.single.mangas.totalCount, 2);
    });

    test('reader chapter provider serves a downloaded chapter offline', () async {
      await db.upsertChapterMetadata(
          id: 99, mangaId: 1, name: 'Ch99', chapterIndex: 5, isRead: false,
          lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
          pageCount: 10, updatedAt: DateTime(2026));
      final c = await _container(db, [
        mangaBookRepositoryProvider.overrideWithValue(_ThrowingMangaBookRepo()),
      ]);
      final ch = await c.read(chapterProvider(chapterId: 99).future);
      expect(ch!.id, 99);
      expect(ch.name, 'Ch99');
    });

    test('mangaDownloadedCount counts only device-downloaded chapters', () async {
      await db.upsertChapterMetadata(
          id: 1, mangaId: 7, name: 'a', chapterIndex: 1, isRead: false,
          lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
          pageCount: 1, updatedAt: DateTime(2026));
      await db.upsertChapterMetadata(
          id: 2, mangaId: 7, name: 'b', chapterIndex: 2, isRead: false,
          lastPageRead: 0, isBookmarked: false, serverIsDownloaded: true,
          pageCount: 1, updatedAt: DateTime(2026));
      await db.setChapterDeviceState(1, OfflineDeviceState.downloaded, bytes: 5);
      final c = await _container(db, const []);
      expect(await c.read(mangaDownloadedCountProvider(7).future), 1);
    });
  });
}
