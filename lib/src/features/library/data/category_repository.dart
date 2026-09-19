// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../global_providers/global_providers.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/network/paginate.dart';
import '../../account/data/graphql/__generated__/account.graphql.dart';
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

  Future<int?> getDefaultCategoryId() async {
    int? after;
    int? defaultId;
    final cursors = <int>{};
    while (true) {
      final page = await ferryClient
          .query$AccountCategoryIdentities(
            Options$Query$AccountCategoryIdentities(
              variables: Variables$Query$AccountCategoryIdentities(
                first: 100,
                after: after,
              ),
            ),
          )
          .getData((data) => data.categories);
      if (page == null) throw StateError('Missing category identities');
      for (final category in page.nodes) {
        if (category.isDefaultCategory) {
          if (defaultId != null && defaultId != category.id) {
            throw StateError('Multiple default categories');
          }
          defaultId = category.id;
        }
      }
      if (!page.pageInfo.hasNextPage) return defaultId;
      after = page.pageInfo.endCursor;
      if (after == null || !cursors.add(after)) {
        throw StateError('Invalid category cursor');
      }
    }
  }

  Future<void> createCategory({required CategoryCreate category}) => ferryClient
      .mutate$CreateCategory(
        Options$Mutation$CreateCategory(
          variables: Variables$Mutation$CreateCategory(input: category),
        ),
      )
      .getData((data) {});

  Future<void> editCategory({
    required int categoryId,
    required CategoryUpdate category,
  }) => ferryClient
      .mutate$UpdateCategory(
        Options$Mutation$UpdateCategory(
          variables: Variables$Mutation$UpdateCategory(
            input: Input$UpdateCategoryInput(id: categoryId, patch: category),
          ),
        ),
      )
      .getData((data) {});

  Future<void> deleteCategory({required int categoryId}) => ferryClient
      .mutate$DeleteCategory(
        Options$Mutation$DeleteCategory(
          variables: Variables$Mutation$DeleteCategory(
            input: Input$DeleteCategoryInput(categoryId: categoryId),
          ),
        ),
      )
      .getData((data) {});

  Future<void> reorderCategory({
    required int categoryId,
    required int position,
  }) => ferryClient
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
      .getData((data) {});

  Future<void> setCategoryMeta({
    required int categoryId,
    required String key,
    required String value,
  }) => ferryClient
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
      .getData((data) {});

  Future<void> deleteCategoryMeta({
    required int categoryId,
    required String key,
  }) => ferryClient
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
      .getData((data) {});

  //  Manga
  //
  // Paginated to exhaustion. This fetch drives BOTH the offline metadata sync
  // (per-manga upsert) and the prune (markNotInLibrary + purgeRemovedLibrary):
  // a single truncated page would leave every series past it unsynced — its
  // inLibraryAt frozen — AND, for off-rule series, stamp the removed sentinel
  // (kLibraryRemovedSentinel) and delete it. The server paginates the
  // `mangas` list (the notification feed pages the sibling `chapters` query
  // the same way), and the old single-shot
  // call kept only the first page while silently discarding pageInfo/totalCount.
  // A partial or failed page therefore yields null — treated by the caller as a
  // failed fetch (no sync, no prune, offline fallback) — never a short list.
  Future<List<MangaDto>?> getAllLibraryMangas() => collectAllPages<MangaDto>(
    (after) => ferryClient
        .query$GetCategoryMangas(
          Options$Query$GetCategoryMangas(
            variables: Variables$Query$GetCategoryMangas(
              filter: Input$MangaFilterInput(
                inLibrary: Input$BooleanFilterInput(equalTo: true),
              ),
              first: 500,
              after: after,
            ),
          ),
        )
        .getData(
          (data) => (
            nodes: data.mangas.nodes,
            hasNextPage: data.mangas.pageInfo.hasNextPage,
            endCursor: data.mangas.pageInfo.endCursor,
            totalCount: data.mangas.totalCount,
          ),
        ),
  );

  Future<List<MangaDto>?> getMangasFromCategory({
    required int categoryId,
    required int? defaultCategoryId,
  }) => ferryClient
      .query$GetCategoryMangas(
        Options$Query$GetCategoryMangas(
          variables: Variables$Query$GetCategoryMangas(
            filter: Input$MangaFilterInput(
              inLibrary: Input$BooleanFilterInput(equalTo: true),
              or: [
                Input$MangaFilterInput(
                  categoryId: Input$IntFilterInput(equalTo: categoryId),
                ),
                if (categoryId == defaultCategoryId)
                  Input$MangaFilterInput(
                    categoryId: Input$IntFilterInput(isNull: true),
                  ),
              ],
            ),
          ),
        ),
      )
      .getData((data) => data.mangas.nodes);
}

@riverpod
CategoryRepository categoryRepository(Ref ref) =>
    CategoryRepository(ref.watch(graphQlClientProvider));
