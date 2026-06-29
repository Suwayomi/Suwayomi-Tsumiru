// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../global_providers/global_providers.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import '../domain/category/category_model.dart';
import './graphql/__generated__/query.graphql.dart';

part 'category_repository.g.dart';

class CategoryRepository {
  final GraphQLClient ferryClient;

  CategoryRepository(this.ferryClient);

  Future<List<CategoryDto>?> getCategoryList() => ferryClient
      .query$AllCategories()
      .getData((data) => data.categories.nodes);

  Future<void> createCategory({required CategoryCreate category}) => ferryClient
      .mutate$CreateCategory(
        Options$Mutation$CreateCategory(
          variables: Variables$Mutation$CreateCategory(input: category),
        ),
      )
      .getData((data) => null);

  Future<void> editCategory({
    required int categoryId,
    required CategoryUpdate category,
  }) =>
      ferryClient
          .mutate$UpdateCategory(
            Options$Mutation$UpdateCategory(
              variables: Variables$Mutation$UpdateCategory(
                input: Input$UpdateCategoryInput(
                  id: categoryId,
                  patch: category,
                ),
              ),
            ),
          )
          .getData((data) => null);

  Future<void> deleteCategory({
    required int categoryId,
  }) =>
      ferryClient
          .mutate$DeleteCategory(
            Options$Mutation$DeleteCategory(
              variables: Variables$Mutation$DeleteCategory(
                input: Input$DeleteCategoryInput(categoryId: categoryId),
              ),
            ),
          )
          .getData((data) => null);

  Future<void> reorderCategory({
    required int categoryId,
    required int position,
  }) =>
      ferryClient
          .mutate$UpdateCategoryOrder(
            Options$Mutation$UpdateCategoryOrder(
              variables: Variables$Mutation$UpdateCategoryOrder(
                input: Input$UpdateCategoryOrderInput(
                  id: categoryId,
                  position: position,
                ),
              ),
            ),
          )
          .getData((data) => null);

  Future<void> setCategoryMeta({
    required int categoryId,
    required String key,
    required String value,
  }) =>
      ferryClient
          .mutate$SetCategoryMeta(
            Options$Mutation$SetCategoryMeta(
              variables: Variables$Mutation$SetCategoryMeta(
                input: Input$SetCategoryMetaInput(
                  meta: Input$CategoryMetaTypeInput(
                    categoryId: categoryId,
                    key: key,
                    value: value,
                  ),
                ),
              ),
            ),
          )
          .getData((data) => null);

  Future<void> deleteCategoryMeta({
    required int categoryId,
    required String key,
  }) =>
      ferryClient
          .mutate$DeleteCategoryMeta(
            Options$Mutation$DeleteCategoryMeta(
              variables: Variables$Mutation$DeleteCategoryMeta(
                input: Input$DeleteCategoryMetaInput(
                  categoryId: categoryId,
                  key: key,
                ),
              ),
            ),
          )
          .getData((data) => null);

  //  Manga
  Future<List<MangaDto>?> getMangasFromCategory({
    required int categoryId,
  }) =>
      ferryClient
          .query$GetCategoryMangas(
            Options$Query$GetCategoryMangas(
              variables: Variables$Query$GetCategoryMangas(
                // Fetch the library entries for this category via the top-level
                // mangas filter (not the category->manga relation, which also
                // returns entries removed from the library — they linger in the
                // DB with inLibrary=false). The virtual "Default" category
                // (id 0) is "in library and uncategorized", so match a null
                // categoryId for it; real categories match by id.
                filter: Input$MangaFilterInput(
                  inLibrary: Input$BooleanFilterInput(equalTo: true),
                  categoryId: categoryId == 0
                      ? Input$IntFilterInput(isNull: true)
                      : Input$IntFilterInput(equalTo: categoryId),
                ),
              ),
            ),
          )
          .getData((data) => data.mangas.nodes);
}

@riverpod
CategoryRepository categoryRepository(Ref ref) =>
    CategoryRepository(ref.watch(graphQlClientProvider));
