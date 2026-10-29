// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../features/offline/data/offline_read_fallback.dart';
import '../../../../../features/offline/data/offline_repository.dart';
import '../../../../../features/offline/data/server_reachability.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/network/graphql_errors.dart';
import '../../../data/category_repository.dart';
import '../../../data/default_category.dart';
import '../../../domain/category/category_model.dart';
import '../../library/controller/library_controller.dart';

part 'edit_category_controller.g.dart';

@riverpod
class CategoryController extends _$CategoryController {
  @override
  Future<List<CategoryDto>?> build() async {
    // Capture dependencies before awaiting: this provider may auto-dispose mid-build.
    final offlineDb = ref.watch(offlineReadDatabaseProvider);
    final viewOffline =
        ref.watch(viewOfflineNowProvider) ||
        ref.watch(serverUnreachableProvider);
    final categoryRepository = ref.watch(categoryRepositoryProvider);
    final sync = ref.read(offlineSyncProvider);
    final defaultIdFuture = ref.watch(defaultCategoryIdProvider.future);
    final defaultId = await defaultIdFuture.catchError((Object _) => null);
    var servedFromCatalog = false;
    final result = await categoriesWithOfflineFallback(
      fetch: () => categoryRepository.getCategoryList(),
      db: offlineDb,
      offlineEnabled: offlineDb != null,
      offlineFirst: viewOffline,
      defaultCategoryId: defaultId,
      onCatalogServe: () => servedFromCatalog = true,
    );
    // Catalog responses are echoes and must not be mirrored back.
    if (sync != null &&
        result != null &&
        defaultId != null &&
        !servedFromCatalog) {
      unawaited(sync.syncCategories(result, defaultCategoryId: defaultId));
    }
    return result;
  }

  Future<AsyncValue<void>> deleteCategory(int categoryId) async {
    final defaultId = ref.read(settledDefaultCategoryIdProvider);
    if (defaultId == null || categoryId == defaultId) {
      return AsyncError(
        StateError('Category cannot be modified'),
        StackTrace.current,
      );
    }
    final response = await AsyncValue.guard(
      () => ref
          .read(categoryRepositoryProvider)
          .deleteCategory(categoryId: categoryId),
    );
    ref.invalidateSelf();
    return response;
  }

  Future<AsyncValue<void>> editCategory(
    int categoryId,
    CategoryUpdate category,
  ) async {
    final defaultId = ref.read(settledDefaultCategoryIdProvider);
    if (defaultId == null || categoryId == defaultId) {
      return AsyncError(
        StateError('Category cannot be modified'),
        StackTrace.current,
      );
    }
    final categoryRepository = ref.read(categoryRepositoryProvider);
    final response = await AsyncValue.guard(
      () => categoryRepository.editCategory(
        categoryId: categoryId,
        category: category,
      ),
    );
    ref.invalidateSelf();
    return response;
  }

  Future<AsyncValue<void>> createCategory(CategoryCreate category) async {
    final categoryRepository = ref.read(categoryRepositoryProvider);
    final response = await AsyncValue.guard(
      () => categoryRepository.createCategory(category: category),
    );
    ref.invalidateSelf();
    return response;
  }

  Future<AsyncValue<void>> reorderCategory(int categoryId, int position) async {
    final defaultId = ref.read(settledDefaultCategoryIdProvider);
    if (defaultId == null || categoryId == defaultId) {
      return AsyncError(
        StateError('Category cannot be modified'),
        StackTrace.current,
      );
    }
    final response = await AsyncValue.guard(
      () => ref
          .read(categoryRepositoryProvider)
          .reorderCategory(categoryId: categoryId, position: position),
    );
    ref.invalidateSelf();
    return response;
  }

  /// Sets server visibility online; offline changes affect only the device mirror until reconnect.
  Future<AsyncValue<CategoryVisibilityOutcome>> setHidden(
    int categoryId,
    bool hidden,
  ) async {
    // Capture dependencies before awaits because this provider auto-disposes.
    final repo = ref.read(categoryRepositoryProvider);
    final offlineDb = ref.read(offlineReadDatabaseProvider);
    final response = await AsyncValue.guard<CategoryVisibilityOutcome>(
      () async {
        hidden
            ? await repo.setCategoryMeta(
                categoryId: categoryId,
                key: kCategoryHiddenMetaKey,
                value: 'true',
              )
            : await repo.deleteCategoryMeta(
                categoryId: categoryId,
                key: kCategoryHiddenMetaKey,
              );
        return CategoryVisibilityOutcome.synced;
      },
    );
    // Unwrap OperationMessageException before classifying connection errors.
    if (response case AsyncError(:final error)
        when isConnectionError(
              error is OperationMessageException ? error.exception : error,
            ) &&
            offlineDb != null) {
      // An unsynced category has no mirror row; report failure if the change cannot persist.
      if (await offlineDb.setCategoryHidden(categoryId, hidden)) {
        ref.invalidateSelf();
        return const AsyncData(CategoryVisibilityOutcome.deviceOnly);
      }
    }
    ref.invalidateSelf();
    return response;
  }
}

/// Device-only changes last until the next server sync.
enum CategoryVisibilityOutcome { synced, deviceOnly }

@riverpod
List<CategoryDto>? categoryListQuery(Ref ref, {required String query}) {
  final categoryList = ref.watch(categoryControllerProvider).value;
  return categoryList
      ?.where((element) => (element.name.query(query)).ifNull())
      .toList();
}

@riverpod
AsyncValue<List<CategoryDto>?> nonZeroCategoryList(Ref ref) {
  final categoryList = ref.watch(categoryControllerProvider);
  // Offline counts measure downloads, so zero does not mean an empty category.
  final offline =
      ref.watch(viewOfflineNowProvider) || ref.watch(serverUnreachableProvider);
  if (offline) return categoryList;
  final defaultLookup = ref.watch(defaultCategoryIdProvider);
  // Unknown default (session expired) would filter out the empty Default category.
  if (!defaultLookup.isLoading && defaultLookup.value == null) {
    return categoryList;
  }
  final defaultId = defaultLookup.value;
  return categoryList.copyWithData(
    (_) => categoryList.value
        ?.where(
          (element) => element.id == defaultId || element.mangas.totalCount > 0,
        )
        .toList(),
  );
}

/// Non-empty library tabs, including hidden categories only when showHiddenCategories is enabled.
/// The edit screen uses the full category list so hidden categories can still be restored.
@riverpod
AsyncValue<List<CategoryDto>?> visibleCategoryList(Ref ref) {
  final categoryList = ref.watch(nonZeroCategoryListProvider);
  final showHidden = ref.watch(showHiddenCategoriesProvider).ifNull(false);
  return categoryList.copyWithData(
    (_) => categoryList.value
        ?.where((element) => showHidden || !element.isHidden)
        .toList(),
  );
}
