// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../global_providers/global_providers.dart';
import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../library/domain/category/category_model.dart';
import '../../domain/chapter/chapter_model.dart';
import '../../domain/chapter_batch/chapter_batch_model.dart';
import '../../domain/chapter_page/chapter_page_model.dart';
import '../../domain/manga/manga_model.dart';
import './__generated__/query.graphql.dart';

part 'manga_book_repository.g.dart';

class MangaBookRepository {
  const MangaBookRepository(this.client);
  final GraphQLClient client;

  Future<MangaDto?> addMangaToLibrary(int mangaId) => client
      .mutate$UpdateManga(
        Options$Mutation$UpdateManga(
          variables: Variables$Mutation$UpdateManga(
            input: Input$UpdateMangaInput(
              id: mangaId,
              patch: Input$UpdateMangaPatchInput(inLibrary: true),
            ),
          ),
        ),
      )
      .getData((data) => data.updateManga?.manga);

  /// Add many series to the library in one request (bulk favorite from browse).
  Future<void> addMangasToLibrary(List<int> mangaIds) => client
      .mutate$UpdateMangas(
        Options$Mutation$UpdateMangas(
          variables: Variables$Mutation$UpdateMangas(
            input: Input$UpdateMangasInput(
              ids: mangaIds,
              patch: Input$UpdateMangaPatchInput(inLibrary: true),
            ),
          ),
        ),
      )
      .getData((data) => null);

  Future<void> removeMangaFromLibrary(int mangaId) => client
      .mutate$UpdateManga(
        Options$Mutation$UpdateManga(
          variables: Variables$Mutation$UpdateManga(
            input: Input$UpdateMangaInput(
              id: mangaId,
              patch: Input$UpdateMangaPatchInput(inLibrary: false),
            ),
          ),
        ),
      )
      .getData((data) => data.updateManga?.manga);

  Future<void> modifyBulkChapters(ChapterBatch batch) => client
      .mutate$UpdateChapters(
        Options$Mutation$UpdateChapters(
          variables: Variables$Mutation$UpdateChapters(input: batch),
        ),
      )
      .getData((data) => null);

  Future<void> deleteChapters(List<int> chapterIds) => client
      .mutate$DeleteDownloadedChapters(
        Options$Mutation$DeleteDownloadedChapters(
          variables: Variables$Mutation$DeleteDownloadedChapters(
            input: Input$DeleteDownloadedChaptersInput(ids: chapterIds),
          ),
        ),
      )
      // Surface failure as a throw so callers don't cascade a device delete
      // when the server delete didn't actually happen.
      .getData((data) => null);

  // Mangas
  Future<MangaDto?> getManga({
    required int mangaId,
  }) =>
      client
          .query$GetManga(Options$Query$GetManga(
            variables: Variables$Query$GetManga(id: mangaId),
          ))
          .getData((data) => data.manga);

  Future<List<CategoryDto>?> getMangaCategoryList({
    required int mangaId,
  }) async =>
      client
          .query$GetMangaCategories(
            Options$Query$GetMangaCategories(
              variables: Variables$Query$GetMangaCategories(id: mangaId),
            ),
          )
          .getData((data) => data.manga.categories.nodes);

  Future<void> addMangaToCategory(int mangaId, int categoryId) => client
      .mutate$UpdateMangaCategories(
        Options$Mutation$UpdateMangaCategories(
          variables: Variables$Mutation$UpdateMangaCategories(
            updateCategoryInput: Input$UpdateMangaCategoriesInput(
              id: mangaId,
              patch: Input$UpdateMangaCategoriesPatchInput(
                addToCategories: [categoryId],
              ),
            ),
          ),
        ),
      )
      .getData((data) => null);

  Future<void> removeMangaFromCategory(int mangaId, int categoryId) => client
      .mutate$UpdateMangaCategories(
        Options$Mutation$UpdateMangaCategories(
          variables: Variables$Mutation$UpdateMangaCategories(
            updateCategoryInput: Input$UpdateMangaCategoriesInput(
              id: mangaId,
              patch: Input$UpdateMangaCategoriesPatchInput(
                removeFromCategories: [categoryId],
              ),
            ),
          ),
        ),
      )
      .getData((data) => null);

  /// Bulk category edit across many series in one request: add [addTo] and
  /// remove [removeFrom] on every id in [mangaIds]. Empty lists are no-ops.
  Future<void> updateMangasCategories(
    List<int> mangaIds, {
    List<int> addTo = const [],
    List<int> removeFrom = const [],
  }) =>
      client
          .mutate$UpdateMangasCategories(
            Options$Mutation$UpdateMangasCategories(
              variables: Variables$Mutation$UpdateMangasCategories(
                input: Input$UpdateMangasCategoriesInput(
                  ids: mangaIds,
                  patch: Input$UpdateMangaCategoriesPatchInput(
                    addToCategories: addTo,
                    removeFromCategories: removeFrom,
                  ),
                ),
              ),
            ),
          )
          .getData((data) => null);

  // Chapters

  Future<ChapterDto?> getChapter({
    required int chapterId,
  }) async =>
      client
          .query$GetChapter(
            Options$Query$GetChapter(
              variables: Variables$Query$GetChapter(
                id: chapterId,
              ),
            ),
          )
          .getData((data) => data.chapter);

  Future<ChapterPagesDto?> getChapterPages({
    required int chapterId,
  }) async =>
      client
          .mutate$GetChapterPages(
            Options$Mutation$GetChapterPages(
              variables: Variables$Mutation$GetChapterPages(
                  input: Input$FetchChapterPagesInput(chapterId: chapterId)),
            ),
          )
          .getData((data) => data.fetchChapterPages);

  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) =>
      client
          .mutate$UpdateChapter(
            Options$Mutation$UpdateChapter(
              variables: Variables$Mutation$UpdateChapter(
                input: Input$UpdateChapterInput(
                  id: chapterId,
                  patch: patch,
                ),
              ),
            ),
          )
          // Surface a failed mutation as a throw (like every other call here),
          // so offline callers detect the failure and keep the change pending
          // instead of clearing the dirty flag on a push that never landed.
          .getData((data) => null);

  Future<void> patchMangaMeta({
    required int mangaId,
    required String key,
    required dynamic value,
  }) async =>
      client
          .mutate$SetMangaMeta(
            Options$Mutation$SetMangaMeta(
              variables: Variables$Mutation$SetMangaMeta(
                input: Input$SetMangaMetaInput(
                  meta: Input$MangaMetaTypeInput(
                    key: key,
                    mangaId: mangaId,
                    value: value,
                  ),
                ),
              ),
            ),
          )
          .getData((data) => null);

  /// Removes a per-series meta override so the app-wide default applies again.
  Future<void> deleteMangaMeta({
    required int mangaId,
    required String key,
  }) async =>
      client
          .mutate$DeleteMangaMeta(
            Options$Mutation$DeleteMangaMeta(
              variables: Variables$Mutation$DeleteMangaMeta(
                input: Input$DeleteMangaMetaInput(
                  key: key,
                  mangaId: mangaId,
                ),
              ),
            ),
          )
          .getData<Object>((data) => null);

  /// Fetches the chapter list FROM THE SOURCE (the server re-scrapes the source
  /// site). Returns nothing if the source is down/gone — callers that need to
  /// survive a dead source should fall back to [getStoredChapterList].
  Future<List<ChapterDto>?> getChapterList(int mangaId) async => client
      .mutate$GetChaptersByMangaId(
        Options$Mutation$GetChaptersByMangaId(
          variables: Variables$Mutation$GetChaptersByMangaId(
            input: Input$FetchChaptersInput(
              mangaId: mangaId,
            ),
          ),
        ),
      )
      .getData((data) => data.fetchChapters?.chapters);

  /// Reads the chapters the server already has STORED for this entry, without
  /// touching the source. Works whenever the server is reachable, even if the
  /// source is down — this is what the WebUI shows.
  Future<List<ChapterDto>?> getStoredChapterList(int mangaId) async => client
      .query$GetChapterPage(
        Options$Query$GetChapterPage(
          variables: Variables$Query$GetChapterPage(
            condition: Input$ChapterConditionInput(mangaId: mangaId),
            order: [
              Input$ChapterOrderInput(
                by: Enum$ChapterOrderBy.SOURCE_ORDER,
                byType: Enum$SortOrder.ASC,
              ),
            ],
          ),
        ),
      )
      .getData((data) => data.chapters.nodes);
}

@riverpod
MangaBookRepository mangaBookRepository(Ref ref) =>
    MangaBookRepository(ref.watch(graphQlClientProvider));
