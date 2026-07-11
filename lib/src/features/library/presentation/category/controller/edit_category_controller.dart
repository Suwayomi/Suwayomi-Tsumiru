// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../features/offline/data/offline_read_fallback.dart';
import '../../../../../features/offline/data/offline_repository.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../data/category_repository.dart';
import '../../../domain/category/category_model.dart';
import '../../library/controller/library_controller.dart';

part 'edit_category_controller.g.dart';

@riverpod
class CategoryController extends _$CategoryController {
  @override
  Future<List<CategoryDto>?> build() async {
    final offlineDb = ref.watch(offlineReadDatabaseProvider);
    final result = await categoriesWithOfflineFallback(
      fetch: () => ref.watch(categoryRepositoryProvider).getCategoryList(),
      db: offlineDb,
      offlineEnabled: offlineDb != null,
    );
    final sync = ref.read(offlineSyncProvider);
    if (sync != null && result != null) {
      unawaited(sync.syncCategories(result));
    }
    return result;
  }

  Future<AsyncValue<void>> deleteCategory(int categoryId) async {
    final response = await AsyncValue.guard(() => ref
        .read(categoryRepositoryProvider)
        .deleteCategory(categoryId: categoryId));
    ref.invalidateSelf();
    return response;
  }

  Future<AsyncValue<void>> editCategory(
      int categoryId, CategoryUpdate category) async {
    final categoryRepository = ref.read(categoryRepositoryProvider);
    final response = await AsyncValue.guard(() => categoryRepository
        .editCategory(categoryId: categoryId, category: category));
    ref.invalidateSelf();
    return response;
  }

  Future<AsyncValue<void>> createCategory(CategoryCreate category) async {
    final categoryRepository = ref.read(categoryRepositoryProvider);
    final response = await AsyncValue.guard(
        () => categoryRepository.createCategory(category: category));
    ref.invalidateSelf();
    return response;
  }

  Future<AsyncValue<void>> reorderCategory(int categoryId, int position) async {
    final response = await AsyncValue.guard(() => ref
        .read(categoryRepositoryProvider)
        .reorderCategory(categoryId: categoryId, position: position));
    ref.invalidateSelf();
    return response;
  }

  /// Hide/show a category from the Library tabs. Stored as a server-side
  /// category meta flag so it persists and syncs across devices.
  Future<AsyncValue<void>> setHidden(int categoryId, bool hidden) async {
    final repo = ref.read(categoryRepositoryProvider);
    final response = await AsyncValue.guard(
      () => hidden
          ? repo.setCategoryMeta(
              categoryId: categoryId,
              key: kCategoryHiddenMetaKey,
              value: 'true',
            )
          : repo.deleteCategoryMeta(
              categoryId: categoryId,
              key: kCategoryHiddenMetaKey,
            ),
    );
    ref.invalidateSelf();
    return response;
  }
}

@riverpod
List<CategoryDto>? categoryListQuery(
  Ref ref, {
  required String query,
}) {
  final categoryList = ref.watch(categoryControllerProvider).valueOrNull;
  return categoryList
      ?.where((element) => (element.name.query(query)).ifNull())
      .toList();
}

@riverpod
AsyncValue<List<CategoryDto>?> nonZeroCategoryList(Ref ref) {
  final categoryList = ref.watch(categoryControllerProvider);
  return categoryList.copyWithData((_) => categoryList.valueOrNull
      ?.where((element) => element.mangas.totalCount > 0)
      .toList());
}

/// Categories shown as tabs on the Library screen: non-empty, and hidden only
/// when [showHiddenCategoriesProvider] is false (the default).
/// The edit screen keeps using the full [categoryControllerProvider] so hidden
/// categories stay listed there (struck-through) and can be unhidden.
@riverpod
AsyncValue<List<CategoryDto>?> visibleCategoryList(Ref ref) {
  final categoryList = ref.watch(nonZeroCategoryListProvider);
  final showHidden = ref.watch(showHiddenCategoriesProvider).ifNull(false);
  return categoryList.copyWithData((_) => categoryList.valueOrNull
      ?.where((element) => showHidden || !element.isHidden)
      .toList());
}
