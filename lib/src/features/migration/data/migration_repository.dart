// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../global_providers/global_providers.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../browse_center/data/source_repository/graphql/__generated__/query.graphql.dart';
import '../../browse_center/domain/source/source_model.dart';
import '../../manga_book/data/downloads/downloads_repository.dart';
import '../../manga_book/data/manga_book/__generated__/query.graphql.dart';
import '../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../manga_book/domain/chapter/chapter_model.dart';
import '../../manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import '../../tracking/data/tracker_repository.dart';
import '../domain/chapter_matcher.dart';
import '../domain/migration_models.dart';

part 'migration_repository.g.dart';

// Rating and custom tags carry regardless of the reader-settings toggle.
const _alwaysMetaKeys = {'flutter_rating', 'flutter_tags'};

// Exclude source-specific scanlators and the obsolete navigation-invert key.
const _readerMetaKeys = {
  'flutter_readerMode',
  'flutter_readerNavigationLayout',
  'flutter_readerPadding',
  'flutter_readerOrientation',
  'flutter_readerTapInvert',
};

abstract class MigrationRepository {
  Future<List<MigrationSource>?> getMigrationSources(
    int mangaId, [
    BuildContext? context,
  ]);
  Future<List<Fragment$MangaDto>?> searchMangaInSource(
    String sourceId,
    String query, [
    BuildContext? context,
  ]);

  /// Copies data without removing the source; removal is a separate journal boundary.
  Future<MigrationCopyResult> copyMangaData(
    int fromMangaId,
    int toMangaId,
    MigrationOption options, [
    BuildContext? context,
  ]);

  /// Idempotently removes the source and unbinds copied records locally, never on the remote tracker.
  Future<({bool success, List<String> warnings})> removeSourceManga(
    int fromMangaId, {
    List<int> copiedSourceRecordIds,
  });

  /// Restores membership without reversing copied chapters, categories, or tracker bindings.
  Future<bool> restoreSourceToLibrary(int mangaId);

  Future<MigrationMergePreflight> preflightMerge(
    int fromMangaId,
    int toMangaId,
  );

  Future<void> cancelMigration();
}

class MigrationRepositoryImpl implements MigrationRepository {
  final GraphQLClient client;

  MigrationRepositoryImpl(this.client);

  @override
  Future<List<MigrationSource>?> getMigrationSources(
    int mangaId, [
    BuildContext? context,
  ]) async {
    try {
      final result = await client.query$SourceList();

      if (result.hasException) {
        throw result.exception!;
      }

      final sources = result.parsedData?.sources.nodes;
      if (sources == null) return null;

      return sources
          .map(
            (source) => MigrationSource(
              id: source.id,
              name: source.displayName,
              lang: source.lang,
              isConfigured: true,
              mangaCount: 0,
              displayName: source.displayName,
              supportsLatest: source.supportsLatest,
            ),
          )
          .toList();
    } catch (e) {
      final errorMessage =
          context?.l10n.errorGettingMigrationSources ??
          'Failed to get migration sources';
      throw Exception('$errorMessage: $e');
    }
  }

  @override
  Future<List<Fragment$MangaDto>?> searchMangaInSource(
    String sourceId,
    String query, [
    BuildContext? context,
  ]) async {
    try {
      final result = await client.mutate$FetchSourceManga(
        Options$Mutation$FetchSourceManga(
          variables: Variables$Mutation$FetchSourceManga(
            withLibraryFields: false,
            withFirstUnread: false,
            input: Input$FetchSourceMangaInput(
              source: sourceId,
              query: query,
              page: 1,
              type: SourceType.SEARCH,
            ),
          ),
        ),
      );

      if (result.hasException) {
        throw result.exception!;
      }

      return result.parsedData?.fetchSourceManga?.mangas ?? [];
    } catch (e) {
      final errorMessage =
          context?.l10n.errorSearchingMangaInSource ??
          'Failed to search manga in source';
      throw Exception('$errorMessage: $e');
    }
  }

  @override
  Future<MigrationCopyResult> copyMangaData(
    int fromMangaId,
    int toMangaId,
    MigrationOption options, [
    BuildContext? context,
  ]) async {
    try {
      final sourceMangaResult = await client.query$GetManga(
        Options$Query$GetManga(
          variables: Variables$Query$GetManga(
            withLibraryFields: false,
            id: fromMangaId,
          ),
        ),
      );

      if (sourceMangaResult.hasException) {
        final errorMessage =
            context?.l10n.errorFetchingSourceManga ??
            'Failed to fetch source manga';
        throw Exception('$errorMessage: ${sourceMangaResult.exception}');
      }

      final sourceManga = sourceMangaResult.parsedData?.manga;
      if (sourceManga == null) {
        final errorMessage =
            context?.l10n.errorSourceMangaNotFound ?? 'Source manga not found';
        throw Exception(errorMessage);
      }

      final targetMangaResult = await client.query$GetManga(
        Options$Query$GetManga(
          variables: Variables$Query$GetManga(
            withLibraryFields: false,
            id: toMangaId,
          ),
        ),
      );

      if (targetMangaResult.hasException) {
        final errorMessage =
            context?.l10n.errorFetchingTargetManga ??
            'Failed to fetch target manga';
        throw Exception('$errorMessage: ${targetMangaResult.exception}');
      }

      final targetManga = targetMangaResult.parsedData?.manga;
      if (targetManga == null) {
        final errorMessage =
            context?.l10n.errorTargetMangaNotFound ?? 'Target manga not found';
        throw Exception(errorMessage);
      }

      List<String> warnings = [];
      int migratedChapters = 0;
      int migratedCategories = 0;
      // Any hard failure blocks source deletion to preserve unmigrated state.
      bool hardFailure = false;

      if (options.migrateCategories && sourceManga.user.inLibrary) {
        try {
          final sourceCategoriesResult = await client.query$GetMangaCategories(
            Options$Query$GetMangaCategories(
              variables: Variables$Query$GetMangaCategories(id: fromMangaId),
            ),
          );

          if (!sourceCategoriesResult.hasException &&
              sourceCategoriesResult.parsedData != null) {
            final categories =
                sourceCategoriesResult.parsedData!.manga.categories.nodes;

            if (categories.isNotEmpty) {
              List<int> categoryIds = categories.map((cat) => cat.id).toList();

              final updateCategoriesResult = await client
                  .mutate$UpdateMangaCategories(
                    Options$Mutation$UpdateMangaCategories(
                      variables: Variables$Mutation$UpdateMangaCategories(
                        updateCategoryInput: Input$UpdateMangaCategoriesInput(
                          id: toMangaId,
                          patch: Input$UpdateMangaCategoriesPatchInput(
                            addToCategories: categoryIds,
                          ),
                        ),
                      ),
                    ),
                  );

              if (updateCategoriesResult.hasException ||
                  updateCategoriesResult.parsedData?.updateMangaCategories ==
                      null) {
                warnings.add(
                  'Failed to migrate categories: ${updateCategoriesResult.exception ?? 'no data'}',
                );
                hardFailure = true;
              } else {
                migratedCategories = categoryIds.length;
              }
            }
          } else {
            warnings.add(
              'Failed to read source categories: ${sourceCategoriesResult.exception ?? 'no data'}',
            );
            hardFailure = true;
          }
        } catch (e) {
          warnings.add('Category migration failed: $e');
          hardFailure = true;
        }
      }

      if (options.migrateChapters) {
        try {
          final sourceChapters = await MangaBookRepository(
            client,
          ).getStoredChapterList(fromMangaId);

          final targetChaptersResult = await client.mutate$GetChaptersByMangaId(
            Options$Mutation$GetChaptersByMangaId(
              variables: Variables$Mutation$GetChaptersByMangaId(
                input: Input$FetchChaptersInput(mangaId: toMangaId),
              ),
            ),
          );

          if (sourceChapters != null &&
              !targetChaptersResult.hasException &&
              targetChaptersResult.parsedData?.fetchChapters?.chapters !=
                  null) {
            final targetChapters =
                targetChaptersResult.parsedData!.fetchChapters!.chapters;

            ChapterState toState(ChapterDto c) => ChapterState(
              id: c.id,
              chapterNumber: c.chapterNumber,
              name: c.name,
              isRead: c.user.isRead,
              isBookmarked: c.user.isBookmarked,
              lastPageRead: c.user.lastPageRead,
            );

            final matchResult = matchChapterState(
              source: sourceChapters.map(toState).toList(),
              target: targetChapters.map(toState).toList(),
            );
            // Unmatched chapter state must block source deletion.
            final int unmatchedState = matchResult.unmatchedState;

            final chapterUpdates = matchResult.patches
                .map(
                  (p) => Input$UpdateChapterInput(
                    id: p.id,
                    patch: Input$UpdateChapterPatchInput(
                      isRead: p.isRead,
                      isBookmarked: p.isBookmarked,
                      lastPageRead: p.lastPageRead,
                    ),
                  ),
                )
                .toList();

            if (chapterUpdates.isNotEmpty) {
              // Serialize chapter updates to avoid overwhelming the server.
              for (final updateInput in chapterUpdates) {
                try {
                  final updateResult = await client.mutate$UpdateChapter(
                    Options$Mutation$UpdateChapter(
                      variables: Variables$Mutation$UpdateChapter(
                        input: updateInput,
                      ),
                    ),
                  );

                  // A null payload does not prove state moved and must block source deletion.
                  if (!updateResult.hasException &&
                      updateResult.parsedData?.updateChapter != null) {
                    migratedChapters++;
                  } else {
                    warnings.add(
                      'Failed to migrate chapter ${updateInput.id}: ${updateResult.exception ?? 'no data'}',
                    );
                    hardFailure = true;
                  }
                } catch (e) {
                  warnings.add(
                    'Failed to migrate chapter ${updateInput.id}: $e',
                  );
                  hardFailure = true;
                }
              }
            }

            if (unmatchedState > 0) {
              warnings.add(
                '$unmatchedState chapter(s) with read/bookmark/progress had no match on the target (likely different chapter numbering); kept the source so that data is not lost.',
              );
              hardFailure = true;
            }
          } else {
            warnings.add(
              'Failed to read chapters for migration: ${targetChaptersResult.exception ?? 'no data'}',
            );
            hardFailure = true;
          }
        } catch (e) {
          warnings.add('Chapter migration failed: $e');
          hardFailure = true;
        }
      }

      // Copy tracker records without an external tracker call when supported; unbind only after migration.
      int migratedTracking = 0;
      final List<int> copiedSourceRecordIds = [];
      if (options.migrateTracking) {
        try {
          final trackerRepo = TrackerRepository(client);
          final useBindRecord = await trackerRepo.supportsBindTrackRecord();
          final sourceRecords = await trackerRepo.getMangaTrackRecords(
            fromMangaId,
          );
          // Keep target tracking unless overwrite was explicitly selected.
          final targetRecords =
              await trackerRepo.getMangaTrackRecords(toMangaId) ?? const [];
          final targetTrackerIds = {for (final r in targetRecords) r.trackerId};
          if (sourceRecords != null) {
            for (final record in sourceRecords) {
              if (targetTrackerIds.contains(record.trackerId) &&
                  !options.overwriteExistingTracking) {
                warnings.add(
                  'Kept the target\'s existing tracking for tracker ${record.trackerId}.',
                );
                continue;
              }
              try {
                await trackerRepo.copyRecord(
                  toMangaId: toMangaId,
                  record: record,
                  useBindTrackRecord: useBindRecord,
                );
                copiedSourceRecordIds.add(record.id);
                migratedTracking++;
              } catch (e) {
                warnings.add(
                  'Failed to migrate tracking record (tracker ${record.trackerId}): $e',
                );
                hardFailure = true;
              }
            }
          } else {
            // Unknown tracking state must block source deletion.
            warnings.add('Failed to read source tracking records.');
            hardFailure = true;
          }
        } catch (e) {
          warnings.add('Tracking migration failed: $e');
          hardFailure = true;
        }
      }

      // Meta overrides are best-effort; a missing override must not block removal.
      try {
        final mangaRepo = MangaBookRepository(client);
        for (final entry in sourceManga.meta) {
          final carry =
              _alwaysMetaKeys.contains(entry.key) ||
              (options.migrateReaderSettings &&
                  _readerMetaKeys.contains(entry.key));
          if (carry) {
            await mangaRepo.patchMangaMeta(
              mangaId: toMangaId,
              key: entry.key,
              value: entry.value,
            );
          }
        }
      } catch (e) {
        warnings.add('Some per-series settings did not carry over: $e');
      }

      if (!hardFailure &&
          sourceManga.user.inLibrary &&
          !targetManga.user.inLibrary) {
        final updateLibraryResult = await client.mutate$UpdateManga(
          Options$Mutation$UpdateManga(
            variables: Variables$Mutation$UpdateManga(
              withLibraryFields: false,
              input: Input$UpdateMangaInput(
                id: toMangaId,
                patch: Input$UpdateMangaPatchInput(inLibrary: true),
              ),
            ),
          ),
        );

        if (updateLibraryResult.hasException ||
            updateLibraryResult.parsedData?.updateManga == null) {
          warnings.add(
            'Failed to add target manga to library: ${updateLibraryResult.exception ?? 'no data'}',
          );
          hardFailure = true;
        }
      }

      return MigrationCopyResult(
        success: !hardFailure,
        sourceInLibrary: sourceManga.user.inLibrary,
        warnings: warnings,
        migratedChapters: migratedChapters,
        migratedCategories: migratedCategories,
        migratedTracking: migratedTracking,
        copiedSourceRecordIds: copiedSourceRecordIds,
        targetTitle: targetManga.title,
        targetSourceId: targetManga.sourceId,
      );
    } catch (e) {
      return MigrationCopyResult(
        success: false,
        sourceInLibrary: false,
        error: 'Migration failed: $e',
      );
    }
  }

  @override
  Future<({bool success, List<String> warnings})> removeSourceManga(
    int fromMangaId, {
    List<int> copiedSourceRecordIds = const [],
  }) async {
    final warnings = <String>[];
    final removeFromLibraryResult = await client.mutate$UpdateManga(
      Options$Mutation$UpdateManga(
        variables: Variables$Mutation$UpdateManga(
          withLibraryFields: false,
          input: Input$UpdateMangaInput(
            id: fromMangaId,
            patch: Input$UpdateMangaPatchInput(inLibrary: false),
          ),
        ),
      ),
    );

    if (removeFromLibraryResult.hasException ||
        removeFromLibraryResult.parsedData?.updateManga == null) {
      warnings.add(
        'Failed to remove source manga from library: ${removeFromLibraryResult.exception ?? 'no data'}',
      );
      return (success: false, warnings: warnings);
    }

    if (copiedSourceRecordIds.isNotEmpty) {
      // Unbind only local source records; never delete the remote tracker entry.
      final trackerRepo = TrackerRepository(client);
      for (final recordId in copiedSourceRecordIds) {
        try {
          await trackerRepo.unbind(
            recordId: recordId,
            deleteRemoteTrack: false,
          );
        } catch (e) {
          warnings.add(
            'Migrated tracking, but could not remove the old source record ($recordId): $e',
          );
        }
      }
    }

    try {
      await cancelQueuedDownloadsForManga(client, fromMangaId);
    } catch (e) {
      warnings.add('Could not cancel queued downloads for the old series: $e');
    }

    return (success: true, warnings: warnings);
  }

  @override
  Future<bool> restoreSourceToLibrary(int mangaId) async {
    final result = await client.mutate$UpdateManga(
      Options$Mutation$UpdateManga(
        variables: Variables$Mutation$UpdateManga(
          withLibraryFields: false,
          input: Input$UpdateMangaInput(
            id: mangaId,
            patch: Input$UpdateMangaPatchInput(inLibrary: true),
          ),
        ),
      ),
    );
    return !result.hasException && result.parsedData?.updateManga != null;
  }

  @override
  Future<MigrationMergePreflight> preflightMerge(
    int fromMangaId,
    int toMangaId,
  ) async {
    final trackerRepo = TrackerRepository(client);
    final targetResult = await client.query$GetManga(
      Options$Query$GetManga(
        variables: Variables$Query$GetManga(
          withLibraryFields: false,
          id: toMangaId,
        ),
      ),
    );
    final targetInLibrary =
        targetResult.parsedData?.manga.user.inLibrary ?? false;
    final sourceRecords =
        await trackerRepo.getMangaTrackRecords(fromMangaId) ?? const [];
    final targetRecords =
        await trackerRepo.getMangaTrackRecords(toMangaId) ?? const [];
    final targetTrackerIds = {for (final r in targetRecords) r.trackerId};
    final colliding = {
      for (final r in sourceRecords)
        if (targetTrackerIds.contains(r.trackerId)) r.trackerId,
    };
    return MigrationMergePreflight(
      targetInLibrary: targetInLibrary,
      collidingTrackerIds: colliding,
    );
  }

  @override
  Future<void> cancelMigration() async {
    throw UnimplementedError('Migration cancellation not yet implemented');
  }
}

@riverpod
MigrationRepository migrationRepository(Ref ref) =>
    MigrationRepositoryImpl(ref.watch(graphQlClientProvider));
