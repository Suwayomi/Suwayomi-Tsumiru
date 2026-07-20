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
import '../../manga_book/data/manga_book/__generated__/query.graphql.dart';
import '../../manga_book/domain/chapter/chapter_model.dart';
import '../../manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import '../../tracking/data/tracker_repository.dart';
import '../domain/migration_models.dart';

part 'migration_repository.g.dart';

abstract class MigrationRepository {
  Future<List<MigrationSource>?> getMigrationSources(int mangaId,
      [BuildContext? context]);
  Future<List<Fragment$MangaDto>?> searchMangaInSource(
      String sourceId, String query,
      [BuildContext? context]);
  Future<MigrationResult?> migrateManga(
      int fromMangaId, int toMangaId, MigrationOption options,
      [BuildContext? context]);
  Future<void> cancelMigration();
}

class MigrationRepositoryImpl implements MigrationRepository {
  final GraphQLClient client;

  MigrationRepositoryImpl(this.client);

  @override
  Future<List<MigrationSource>?> getMigrationSources(int mangaId,
      [BuildContext? context]) async {
    try {
      final result = await client.query$SourceList();

      if (result.hasException) {
        throw result.exception!;
      }

      final sources = result.parsedData?.sources.nodes;
      if (sources == null) return null;

      return sources
          .map((source) => MigrationSource(
                id: source.id,
                name: source.displayName,
                lang: source.lang,
                isConfigured: true,
                mangaCount: 0,
                displayName: source.displayName,
                supportsLatest: source.supportsLatest,
              ))
          .toList();
    } catch (e) {
      final errorMessage = context?.l10n.errorGettingMigrationSources ??
          'Failed to get migration sources';
      throw Exception('$errorMessage: $e');
    }
  }

  @override
  Future<List<Fragment$MangaDto>?> searchMangaInSource(
      String sourceId, String query,
      [BuildContext? context]) async {
    try {
      final result = await client.mutate$FetchSourceManga(
        Options$Mutation$FetchSourceManga(
          variables: Variables$Mutation$FetchSourceManga(
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
      final errorMessage = context?.l10n.errorSearchingMangaInSource ??
          'Failed to search manga in source';
      throw Exception('$errorMessage: $e');
    }
  }

  @override
  Future<MigrationResult?> migrateManga(
      int fromMangaId, int toMangaId, MigrationOption options,
      [BuildContext? context]) async {
    try {
      final sourceMangaResult = await client.query$GetManga(
        Options$Query$GetManga(
          variables: Variables$Query$GetManga(id: fromMangaId),
        ),
      );

      if (sourceMangaResult.hasException) {
        final errorMessage = context?.l10n.errorFetchingSourceManga ??
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
          variables: Variables$Query$GetManga(id: toMangaId),
        ),
      );

      if (targetMangaResult.hasException) {
        final errorMessage = context?.l10n.errorFetchingTargetManga ??
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
      // Set on any hard failure below; blocks deleting the source so a partial
      // migration can't lose data (better a visible duplicate than gone).
      bool hardFailure = false;

      // Step 1: Add target manga to library if source manga is in library
      if (sourceManga.inLibrary) {
        final updateLibraryResult = await client.mutate$UpdateManga(
          Options$Mutation$UpdateManga(
            variables: Variables$Mutation$UpdateManga(
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
              'Failed to add target manga to library: ${updateLibraryResult.exception ?? 'no data'}');
          hardFailure = true;
        }
      }

      // Step 2: Migrate categories if enabled
      if (options.migrateCategories && sourceManga.inLibrary) {
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

              final updateCategoriesResult =
                  await client.mutate$UpdateMangaCategories(
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
                    'Failed to migrate categories: ${updateCategoriesResult.exception ?? 'no data'}');
                hardFailure = true;
              } else {
                migratedCategories = categoryIds.length;
              }
            }
          } else {
            // The fetch itself failed — treat as a hard failure so we don't
            // delete the source having migrated nothing.
            warnings.add(
                'Failed to read source categories: ${sourceCategoriesResult.exception ?? 'no data'}');
            hardFailure = true;
          }
        } catch (e) {
          warnings.add('Category migration failed: $e');
          hardFailure = true;
        }
      }

      // Step 3: Migrate reading progress if enabled
      if (options.migrateChapters) {
        try {
          final sourceChaptersResult = await client.mutate$GetChaptersByMangaId(
            Options$Mutation$GetChaptersByMangaId(
              variables: Variables$Mutation$GetChaptersByMangaId(
                input: Input$FetchChaptersInput(mangaId: fromMangaId),
              ),
            ),
          );

          final targetChaptersResult = await client.mutate$GetChaptersByMangaId(
            Options$Mutation$GetChaptersByMangaId(
              variables: Variables$Mutation$GetChaptersByMangaId(
                input: Input$FetchChaptersInput(mangaId: toMangaId),
              ),
            ),
          );

          if (!sourceChaptersResult.hasException &&
              !targetChaptersResult.hasException &&
              sourceChaptersResult.parsedData?.fetchChapters?.chapters !=
                  null &&
              targetChaptersResult.parsedData?.fetchChapters?.chapters !=
                  null) {
            final sourceChapters =
                sourceChaptersResult.parsedData!.fetchChapters!.chapters;
            final targetChapters =
                targetChaptersResult.parsedData!.fetchChapters!.chapters;

            List<Input$UpdateChapterInput> chapterUpdates = [];
            // Source chapters carrying state (read / bookmark / partial progress)
            // that has no target match — that state can't migrate, so it must
            // block deleting the source.
            int unmatchedState = 0;
            // Merge state per target id, seeded from the target's own state, so
            // several source chapters matching one target (via the number
            // tolerance or a name fallback) can't overwrite higher progress with
            // lower: read/bookmark OR together, position takes the max.
            final merged = <int, ({bool read, bool bookmark, int lastPage})>{};

            for (final sourceChapter in sourceChapters) {
              // Migrate any chapter with state to carry over, not just read ones
              // — a bookmarked or partially-read (unread) chapter counts too.
              final hasState = sourceChapter.isRead ||
                  sourceChapter.isBookmarked ||
                  sourceChapter.lastPageRead > 0;
              if (!hasState) continue;

              ChapterDto? matchingChapter;

              // First, try exact chapter number match
              matchingChapter = targetChapters
                  .where(
                    (chapter) =>
                        (chapter.chapterNumber - sourceChapter.chapterNumber)
                            .abs() <
                        0.01,
                  )
                  .firstOrNull;

              // If no exact match, try name matching (case insensitive)
              if (matchingChapter == null && sourceChapter.name.isNotEmpty) {
                final sourceName = sourceChapter.name.toLowerCase().trim();
                matchingChapter = targetChapters
                    .where(
                      (chapter) =>
                          chapter.name.toLowerCase().trim() == sourceName,
                    )
                    .firstOrNull;
              }

              // If still no match, try partial name matching
              if (matchingChapter == null && sourceChapter.name.isNotEmpty) {
                final sourceName = sourceChapter.name.toLowerCase().trim();
                matchingChapter = targetChapters.where(
                  (chapter) {
                    final targetName = chapter.name.toLowerCase().trim();
                    return targetName.contains(sourceName) ||
                        sourceName.contains(targetName);
                  },
                ).firstOrNull;
              }

              if (matchingChapter == null) {
                unmatchedState++;
                continue;
              }

              final prev = merged[matchingChapter.id] ??
                  (
                    read: matchingChapter.isRead,
                    bookmark: matchingChapter.isBookmarked,
                    lastPage: matchingChapter.lastPageRead,
                  );
              merged[matchingChapter.id] = (
                read: prev.read || sourceChapter.isRead,
                bookmark: prev.bookmark || sourceChapter.isBookmarked,
                lastPage: sourceChapter.lastPageRead > prev.lastPage
                    ? sourceChapter.lastPageRead
                    : prev.lastPage,
              );
            }

            // Emit an update per target only when the merged state ADDS something
            // over the target's own state — never un-read, un-bookmark, or rewind.
            for (final entry in merged.entries) {
              final original =
                  targetChapters.firstWhere((c) => c.id == entry.key);
              final m = entry.value;
              final setRead = m.read && !original.isRead;
              final setBookmark = m.bookmark && !original.isBookmarked;
              // Carry the furthest position independently of read state — a read
              // chapter can still record where it was left off, and losing the
              // merged max here would silently drop migrated progress.
              final setPosition = m.lastPage > original.lastPageRead;
              if (setRead || setBookmark || setPosition) {
                chapterUpdates.add(
                  Input$UpdateChapterInput(
                    id: entry.key,
                    patch: Input$UpdateChapterPatchInput(
                      isRead: setRead ? true : null,
                      isBookmarked: setBookmark ? true : null,
                      lastPageRead: setPosition ? m.lastPage : null,
                    ),
                  ),
                );
              }
            }

            if (chapterUpdates.isNotEmpty) {
              // Update chapters one by one to avoid overwhelming the server
              for (final updateInput in chapterUpdates) {
                try {
                  final updateResult = await client.mutate$UpdateChapter(
                    Options$Mutation$UpdateChapter(
                        variables: Variables$Mutation$UpdateChapter(
                            input: updateInput)),
                  );

                  // A null payload (no exception, but the server applied
                  // nothing) must not count as migrated, or the source could be
                  // deleted with state unmoved.
                  if (!updateResult.hasException &&
                      updateResult.parsedData?.updateChapter != null) {
                    migratedChapters++;
                  } else {
                    warnings.add(
                        'Failed to migrate chapter ${updateInput.id}: ${updateResult.exception ?? 'no data'}');
                    hardFailure = true;
                  }
                } catch (e) {
                  warnings
                      .add('Failed to migrate chapter ${updateInput.id}: $e');
                  hardFailure = true;
                }
              }
            }

            // Any chapter with state and no target match means that state can't
            // migrate — keep the source so that data isn't lost.
            if (unmatchedState > 0) {
              warnings.add(
                  '$unmatchedState chapter(s) with read/bookmark/progress had no match on the target (likely different chapter numbering); kept the source so that data is not lost.');
              hardFailure = true;
            }
          } else {
            // The fetch itself failed — treat as a hard failure so we don't
            // delete the source having migrated no read progress.
            warnings.add(
                'Failed to read chapters for migration: ${sourceChaptersResult.exception ?? targetChaptersResult.exception ?? 'no data'}');
            hardFailure = true;
          }
        } catch (e) {
          warnings.add('Chapter migration failed: $e');
          hardFailure = true;
        }
      }

      // Step 4: Migrate tracking records if enabled
      int migratedTracking = 0;
      if (options.migrateTracking) {
        try {
          final trackerRepo = TrackerRepository(client);
          final sourceRecords =
              await trackerRepo.getMangaTrackRecords(fromMangaId);
          if (sourceRecords != null) {
            for (final record in sourceRecords) {
              try {
                await trackerRepo.bind(
                  mangaId: toMangaId,
                  trackerId: record.trackerId,
                  remoteId: record.remoteId,
                  private: record.private,
                );
                migratedTracking++;
              } catch (e) {
                warnings.add(
                    'Failed to migrate tracking record (tracker ${record.trackerId}): $e');
                hardFailure = true;
              }
            }
          } else {
            // A null result (degraded/no data, no exception) means the tracking
            // state was never read — treat as a hard failure so we don't delete
            // a source whose tracking might not have migrated.
            warnings.add('Failed to read source tracking records.');
            hardFailure = true;
          }
        } catch (e) {
          warnings.add('Tracking migration failed: $e');
          hardFailure = true;
        }
      }

      // Step 5: Remove the source from the library only if enabled AND nothing
      // hard-failed above — otherwise deleting it would lose the data that
      // didn't migrate. Leave the (visible) duplicate instead.
      if (options.deleteSource && sourceManga.inLibrary && hardFailure) {
        warnings.add(
            'Kept the source in your library: parts of the migration failed, '
            'so removing it would lose data.');
      } else if (options.deleteSource && sourceManga.inLibrary) {
        final removeFromLibraryResult = await client.mutate$UpdateManga(
          Options$Mutation$UpdateManga(
            variables: Variables$Mutation$UpdateManga(
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
              'Failed to remove source manga from library: ${removeFromLibraryResult.exception ?? 'no data'}');
          hardFailure = true;
        }
      }

      warnings.add(hardFailure
          ? 'Migration finished with some failures (see above).'
          : 'Migration completed successfully! ✅');
      warnings.add('• Target manga: ${targetManga.title}');
      warnings.add('• Source: ${targetManga.sourceId}');
      if (migratedChapters > 0) {
        warnings.add('• Chapters migrated: $migratedChapters');
      }
      if (migratedCategories > 0) {
        warnings.add('• Categories migrated: $migratedCategories');
      }
      if (migratedTracking > 0) {
        warnings.add('• Tracking records migrated: $migratedTracking');
      }

      return MigrationResult(
        // A hard failure means the migration didn't fully complete its intent
        // (and the source was deliberately kept) — report that honestly.
        success: !hardFailure,
        migratedChapters: migratedChapters,
        migratedCategories: migratedCategories,
        migratedTracking: migratedTracking,
        warnings: warnings,
      );
    } catch (e) {
      return MigrationResult(
        success: false,
        error: 'Migration failed: $e',
      );
    }
  }

  @override
  Future<void> cancelMigration() async {
    throw UnimplementedError('Migration cancellation not yet implemented');
  }
}

@riverpod
MigrationRepository migrationRepository(Ref ref) =>
    MigrationRepositoryImpl(ref.watch(graphQlClientProvider));
