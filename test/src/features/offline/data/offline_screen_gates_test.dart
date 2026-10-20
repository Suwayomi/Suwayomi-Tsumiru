// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/data/category_repository.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../../helpers/offline_test_db.dart';

class _ThrowingCategoryRepo implements CategoryRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw const SocketException('offline');
}

class _ThrowingMangaBookRepo implements MangaBookRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw const SocketException('offline');
}

Future<ProviderContainer> _container(
  OfflineDatabase db,
  List<Override> extra,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      offlineDatabaseProvider.overrideWithValue(db),
      offlineEnabledProvider.overrideWithValue(true),
      offlineActiveProvider.overrideWithValue(true),
      ...extra,
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  group('offlineDefaultCategoryDto', () {});

  group('chapterMetaWithOfflineFallback', () {});

  // The bugs Aaron actually hit: the real gating providers must render offline,
  // not just the helpers in isolation.
  test('real gating providers render offline', () async {
    await db.upsertMangaMetadata(
      id: 1,
      title: 'Saved',
      updatedAt: DateTime(2026),
    );
    await db.upsertChapterMetadata(
      id: 99,
      mangaId: 1,
      name: 'Ch99',
      chapterIndex: 5,
      isRead: false,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: true,
      pageCount: 10,
      updatedAt: DateTime(2026),
    );
    await db.setChapterDeviceState(99, OfflineDeviceState.downloaded, bytes: 1);

    final reader = await _container(db, [
      mangaBookRepositoryProvider.overrideWithValue(_ThrowingMangaBookRepo()),
    ]);
    final ch = await reader.read(chapterProvider(chapterId: 99).future);
    expect(ch!.id, 99);
    expect(ch.name, 'Ch99');

    final list = await _container(db, [
      categoryRepositoryProvider.overrideWithValue(_ThrowingCategoryRepo()),
    ]);
    final mangas = await list.read(categoryMangaListProvider(0).future);
    expect(mangas!.map((m) => m.id), [1]);
  });
}
