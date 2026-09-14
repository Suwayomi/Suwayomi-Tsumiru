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
    // Capture every ref-backed dependency BEFORE the await. This provider
    // auto-disposes and can be torn down mid-build (e.g. add-to-library reading
    // .future), after which any ref access throws "used after it has been
    // disposed" — the crash this guards against.
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
    // A catalog-served list is an echo — never mirror it back.
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

  /// Hide/show a category from the Library tabs. Stored as a server-side
  /// category meta flag so it persists and syncs across devices. Offline,
  /// the change lands on the device's mirror instead — downloads in a hidden
  /// category must stay reachable — and the server's flag reasserts on the
  /// next online sync.
  Future<AsyncValue<CategoryVisibilityOutcome>> setHidden(
    int categoryId,
    bool hidden,
  ) async {
    // Captured before the awaits: this provider auto-disposes (see build).
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
    // The repository throws OperationMessageException wrapping the link
    // error — unwrap before classifying, same as _shouldFallBack.
    if (response case AsyncError(:final error)
        when isConnectionError(
              error is OperationMessageException ? error.exception : error,
            ) &&
            offlineDb != null) {
      // A mirror without this row (never synced online) can't honor the
      // change — fall through to the error rather than claim success.
      if (await offlineDb.setCategoryHidden(categoryId, hidden)) {
        ref.invalidateSelf();
        return const AsyncData(CategoryVisibilityOutcome.deviceOnly);
      }
    }
    ref.invalidateSelf();
    return response;
  }
}

/// How a category visibility change landed: on the server (permanent,
/// cross-device) or only on this device's offline mirror (until reconnect).
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
  // Offline the count is "how much of this category is downloaded", so zero
  // means not-downloaded-yet, not empty. Dropping those took the whole tab bar
  // with them whenever a user's downloads sat in one category — their other
  // categories looked deleted, with no way to reach them.
  final offline =
      ref.watch(viewOfflineNowProvider) || ref.watch(serverUnreachableProvider);
  if (offline) return categoryList;
  final defaultId = ref.watch(settledDefaultCategoryIdProvider);
  return categoryList.copyWithData(
    (_) => categoryList.value
        ?.where(
          (element) => element.id == defaultId || element.mangas.totalCount > 0,
        )
        .toList(),
  );
}

/// Categories shown as tabs on the Library screen: non-empty, and hidden only
/// when [showHiddenCategoriesProvider] is false (the default).
/// The edit screen keeps using the full [categoryControllerProvider] so hidden
/// categories stay listed there (struck-through) and can be unhidden.
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
