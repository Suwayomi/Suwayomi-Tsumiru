// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/data/category_repository.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import '../../../../helpers/offline_test_db.dart';

class _ThrowingCategoryRepo implements CategoryRepository {
  @override
  Future<List<MangaDto>?> getMangasFromCategory({required int categoryId}) =>
      throw Exception('offline');

  @override
  dynamic noSuchMethod(Invocation i) => throw Exception('offline');
}

void main() {
  test('categoryMangaList falls back to the offline catalog on server error',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = testOfflineDatabase();
    addTearDown(db.close);
    await db.upsertMangaMetadata(
        id: 1, title: 'Saved', updatedAt: DateTime(2026));

    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      offlineDatabaseProvider.overrideWithValue(db),
      offlineEnabledProvider.overrideWithValue(true),
      categoryRepositoryProvider.overrideWithValue(_ThrowingCategoryRepo()),
    ]);
    addTearDown(c.dispose);

    final list = await c.read(categoryMangaListProvider(0).future);
    expect(list!.map((m) => m.id), [1]);
  });
}
