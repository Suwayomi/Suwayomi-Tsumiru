// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../global_providers/global_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../browse_center/data/source_repository/source_repository.dart';
import '../../browse_center/domain/source/source_model.dart';
import '../../browse_center/presentation/source/controller/source_controller.dart';
import '../../library/presentation/category/controller/edit_category_controller.dart';
import '../../library/presentation/library/controller/library_controller.dart';
import '../../library/presentation/library/controller/library_manga_list.dart';
import '../../manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import '../../manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import '../../settings/presentation/browse/widgets/show_nsfw_switch/show_nsfw_switch.dart';
import '../data/migration_repository.dart';
import '../domain/migration_models.dart';

part 'migration_controller.g.dart';

@riverpod
class MigrationSources extends _$MigrationSources {
  @override
  Future<List<MigrationSource>?> build({required int mangaId}) async {
    final sources = await ref
        .watch(migrationRepositoryProvider)
        .getMigrationSources(mangaId);
    if (sources == null) return null;
    // Respect "Show NSFW" here too: MigrationSource carries no nsfw flag, so
    // exclude any migration source whose id is a known NSFW source. Defaults to
    // showing NSFW (no filtering) when the setting is unset, matching the
    // Sources/Extensions lists.
    if (ref.watch(showNSFWProvider).ifNull(true)) return sources;
    final nsfwIds = {
      for (final e
          in await ref.watch(sourceListProvider.future) ?? const <SourceDto>[])
        if (e.isNsfw) e.id,
    };
    return [...sources.where((e) => !nsfwIds.contains(e.id))];
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

@riverpod
class MigrationSearch extends _$MigrationSearch {
  @override
  Future<List<Fragment$MangaDto>?> build({
    required String sourceId,
    required String query,
  }) async {
    if (query.isEmpty) return [];

    return ref
        .watch(migrationRepositoryProvider)
        .searchMangaInSource(sourceId, query);
  }

  Future<void> search(String sourceId, String query) async {
    state = const AsyncLoading();

    final result = await AsyncValue.guard(() async {
      return await ref
          .read(migrationRepositoryProvider)
          .searchMangaInSource(sourceId, query);
    });
    if (!ref.mounted) return;
    state = result;
  }

  void clearResults() {
    state = const AsyncData([]);
  }
}

// Migration Quick Search Results similar to regular global search
typedef MigrationQuickSearchResults = ({
  SourceDto source,
  AsyncValue<List<MangaDto>> mangaList
});

@riverpod
Future<List<MangaDto>> migrationSourceQuickSearchMangaList(
  Ref ref,
  String sourceId, {
  String? query,
}) async {
  final rateLimiterQueue = ref.watch(rateLimitQueueProvider(query));
  // Capture now — ref access after the gap may throw once disposed.
  final sourceRepository = ref.watch(sourceRepositoryProvider);
  final mangaPage = await rateLimiterQueue
      .add(() => sourceRepository.fetchSourceManga(
            page: 1,
            sourceId: sourceId,
            sourceType: SourceType.SEARCH,
            query: query,
          ));
  return [...?(mangaPage?.mangas)];
}

@riverpod
AsyncValue<List<MigrationQuickSearchResults>> migrationGlobalSearchResults(
    Ref ref,
    {String? query}) {
  // Pinned-first list of every searchable source (shared with global search;
  // pinned sources are otherwise excluded from the grouped map).
  final sourcesData = ref.watch(searchableSourcesProvider);
  final sourceList = sourcesData.value ?? const <SourceDto>[];

  final List<MigrationQuickSearchResults> sourceMangaListPairList = [];
  for (SourceDto source in sourceList) {
    if (source.id.isNotBlank) {
      final mangaList = ref.watch(
        migrationSourceQuickSearchMangaListProvider(source.id, query: query),
      );
      sourceMangaListPairList.add((mangaList: mangaList, source: source));
    }
  }

  return sourcesData.copyWithData((_) => sourceMangaListPairList);
}

@riverpod
class MigrationExecution extends _$MigrationExecution {
  @override
  MigrationProgress? build() => null;

  Future<MigrationResult?> executeMigration({
    required int fromMangaId,
    required int toMangaId,
    required MigrationOption options,
  }) async {
    try {
      state = const MigrationProgress(
        currentStep: MigrationStep.preparingMigration,
        percentage: 0.0,
        status: MigrationStatus.preparing,
      );

      await Future.delayed(const Duration(milliseconds: 1000));

      state = const MigrationProgress(
        currentStep: MigrationStep.migrateChapters,
        percentage: 25.0,
        status: MigrationStatus.migrating,
      );

      await Future.delayed(const Duration(milliseconds: 800));

      state = const MigrationProgress(
        currentStep: MigrationStep.migrateCategories,
        percentage: 50.0,
        status: MigrationStatus.migrating,
      );

      await Future.delayed(const Duration(milliseconds: 600));

      state = const MigrationProgress(
        currentStep: MigrationStep.migrationInProgress,
        percentage: 75.0,
        status: MigrationStatus.migrating,
      );

      final result = await ref
          .read(migrationRepositoryProvider)
          .migrateManga(fromMangaId, toMangaId, options);

      if (result?.success == true) {
        state = const MigrationProgress(
          currentStep: MigrationStep.migrationCompleted,
          percentage: 100.0,
          status: MigrationStatus.completed,
        );

        await _invalidateCachesAfterMigration(fromMangaId, toMangaId);
      } else {
        state = MigrationProgress(
          currentStep: MigrationStep.migrationFailed,
          percentage: 0.0,
          status: MigrationStatus.error,
          errorMessage: result?.error,
        );
      }

      return result;
    } catch (e) {
      state = MigrationProgress(
        currentStep: MigrationStep.migrationFailed,
        status: MigrationStatus.error,
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  Future<void> cancelMigration() async {
    try {
      await ref.read(migrationRepositoryProvider).cancelMigration();
      state = const MigrationProgress(
        currentStep: MigrationStep.migrationCancelled,
        status: MigrationStatus.cancelled,
      );
    } catch (e) {
      // Handle cancellation error - for now just set to cancelled since cancellation isn't implemented
      state = const MigrationProgress(
        currentStep: MigrationStep.migrationCancelled,
        status: MigrationStatus.cancelled,
      );
    }
  }

  void reset() {
    state = null;
  }

  Future<void> _invalidateCachesAfterMigration(
      int fromMangaId, int toMangaId) async {
    try {
      ref.invalidate(mangaWithIdProvider(mangaId: fromMangaId));
      ref.invalidate(mangaWithIdProvider(mangaId: toMangaId));

      // Invalidate chapter lists for both manga (needed for unread count refresh)
      ref.invalidate(mangaChapterListProvider(mangaId: fromMangaId));
      ref.invalidate(mangaChapterListProvider(mangaId: toMangaId));

      // Invalidate the full library fetch (source of truth) then the
      // per-category slices so all reactive descendants re-partition.
      ref.invalidate(libraryMangaListProvider);
      final categories = ref.read(categoryControllerProvider).value ?? [];
      for (final category in categories) {
        ref.invalidate(categoryMangaListProvider(category.id));
      }
      // Also invalidate the default "All" category (id: 0)
      ref.invalidate(categoryMangaListProvider(0));

      // Small delay to ensure cache invalidation propagates
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      // Don't throw - cache invalidation errors shouldn't fail the migration
    }
  }
}

@riverpod
class MigrationSearchQuery extends _$MigrationSearchQuery {
  @override
  String build() => '';

  void update(String query) {
    state = query;
  }

  void clear() {
    state = '';
  }
}

@riverpod
class SelectedMigrationSource extends _$SelectedMigrationSource {
  @override
  MigrationSource? build() => null;

  void select(MigrationSource source) {
    state = source;
  }

  void clear() {
    state = null;
  }
}

@riverpod
class SelectedTargetManga extends _$SelectedTargetManga {
  @override
  Fragment$MangaDto? build() => null;

  void select(Fragment$MangaDto manga) {
    state = manga;
  }

  void clear() {
    state = null;
  }
}

@riverpod
class MigrationOptions extends _$MigrationOptions {
  @override
  MigrationOption build() => const MigrationOption();

  void update(MigrationOption options) {
    state = options;
  }

  void updateChapters(bool value) {
    state = state.copyWith(migrateChapters: value);
  }

  void updateCategories(bool value) {
    state = state.copyWith(migrateCategories: value);
  }

  void updateDownloads(bool value) {
    state = state.copyWith(migrateDownloads: value);
  }

  void updateTracking(bool value) {
    state = state.copyWith(migrateTracking: value);
  }

  void updateDeleteSource(bool value) {
    state = state.copyWith(deleteSource: value);
  }

  void reset() {
    state = const MigrationOption();
  }
}
