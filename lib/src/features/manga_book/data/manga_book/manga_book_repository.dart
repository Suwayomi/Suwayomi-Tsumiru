// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../global_providers/global_providers.dart';
import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/webui_meta/webui_meta_codec.dart';
import '../../../../utils/webui_meta/webui_meta_repository.dart';
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
            withLibraryFields: false,
            input: Input$UpdateMangaInput(
              id: mangaId,
              patch: Input$UpdateMangaPatchInput(inLibrary: true),
            ),
          ),
        ),
      )
      .getData((data) => data.updateManga?.manga);

  /// Returns only server-confirmed IDs; a partial apply may return fewer than [mangaIds].
  Future<List<int>> addMangasToLibrary(List<int> mangaIds) => client
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
      .getData((data) => data.updateMangas?.mangas.map((m) => m.id).toList())
      .then((ids) => ids ?? const []);

  Future<void> removeMangaFromLibrary(int mangaId) async {
    final metas = await WebUiMetaRepository(client).readGlobalMetas();
    final forget = readWebUiValue(metas, 'removeMangaFromCategories');
    final removed = await client
      .mutate$UpdateManga(
        Options$Mutation$UpdateManga(
          variables: Variables$Mutation$UpdateManga(
              withLibraryFields: false,
            input: Input$UpdateMangaInput(
              id: mangaId,
              patch: Input$UpdateMangaPatchInput(inLibrary: false),
            ),
          ),
        ),
      )
      .getData((data) => data.updateManga?.manga);
    if (removed == null || removed.user.inLibrary) {
      throw StateError('Library removal was not confirmed');
    }
    if (forget != null && decodeWebUiBool(forget)) {
      await updateMangasCategories([mangaId], clearCategories: true);
    }
  }

  Future<void> modifyBulkChapters(ChapterBatch batch) => client
      .mutate$UpdateChapters(
        Options$Mutation$UpdateChapters(
          variables: Variables$Mutation$UpdateChapters(input: batch),
        ),
      )
      .getData((data) {});

  Future<void> deleteChapters(List<int> chapterIds) => client
      .mutate$DeleteDownloadedChapters(
        Options$Mutation$DeleteDownloadedChapters(
          variables: Variables$Mutation$DeleteDownloadedChapters(
            input: Input$DeleteDownloadedChaptersInput(ids: chapterIds),
          ),
        ),
      )
      // Throw on server failure so callers do not delete the device copy.
      .getData((data) {});

  Future<MangaDto?> getManga({
    required int mangaId,
  }) =>
      client
          .query$GetManga(Options$Query$GetManga(
          variables: Variables$Query$GetManga(
            withLibraryFields: false,
            id: mangaId,
          ),
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
      .getData((data) {});

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
      .getData((data) {});

  /// Empty [addTo] and [removeFrom] lists are no-ops.
  Future<void> updateMangasCategories(
    List<int> mangaIds, {
    List<int> addTo = const [],
    List<int> removeFrom = const [],
    bool clearCategories = false,
  }) =>
      client
          .mutate$UpdateMangasCategories(
            Options$Mutation$UpdateMangasCategories(
              variables: Variables$Mutation$UpdateMangasCategories(
                input: Input$UpdateMangasCategoriesInput(
                  ids: mangaIds,
                  patch: Input$UpdateMangaCategoriesPatchInput(
                clearCategories: clearCategories,
                    addToCategories: addTo,
                    removeFromCategories: removeFrom,
                  ),
                ),
              ),
            ),
          )
          .getData((data) {});


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
          // Throw on failure so offline callers keep the change pending.
          .getData((data) {});

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
          .getData((data) {});

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

  /// Re-scrapes the source; fall back to [getStoredChapterList] if the source is unavailable.
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

  /// Fetches metadata and chapters; Tachiyomix 1.6+ chapters-only fetches do not populate metadata.
  Future<List<ChapterDto>?> getMangaAndChapterList(int mangaId) async => client
      .mutate$GetMangaAndChaptersByMangaId(
        Options$Mutation$GetMangaAndChaptersByMangaId(
          variables: Variables$Mutation$GetMangaAndChaptersByMangaId(
            input: Input$FetchMangaAndChaptersInput(
              id: mangaId,
              fetchManga: true,
              fetchChapters: true,
            ),
          ),
        ),
      )
      .getData((data) => data.fetchMangaAndChapters?.chapters);

  /// Reads stored server chapters without contacting the source.
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

// Keep the repository alive across in-flight progress writes.
@Riverpod(keepAlive: true)
MangaBookRepository mangaBookRepository(Ref ref) =>
    MangaBookRepository(ref.watch(graphQlClientProvider));
