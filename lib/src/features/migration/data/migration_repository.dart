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
import '../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../manga_book/domain/chapter/chapter_model.dart';
import '../../manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import '../../tracking/data/tracker_repository.dart';
import '../domain/chapter_matcher.dart';
import '../domain/migration_models.dart';

part 'migration_repository.g.dart';

/// Your rating and custom tags describe the STORY, not the source, so they carry
/// on every migration regardless of the reader-settings toggle.
const _alwaysMetaKeys = {
  'flutter_rating',
  'flutter_tags',
};

/// Per-manga reader/display settings, carried when the reader-settings toggle is
/// on. Deliberately NOT `flutter_scanlator` (names scanlators the new source
/// doesn't have) nor the dead legacy `flutter_readerNavigationLayoutInvert`.
const _readerMetaKeys = {
  'flutter_readerMode',
  'flutter_readerNavigationLayout',
  'flutter_readerPadding',
  'flutter_readerMagnifierSize',
  'flutter_readerOrientation',
  'flutter_readerTapInvert',
  'flutter_chapterListMode',
};

abstract class MigrationRepository {
  Future<List<MigrationSource>?> getMigrationSources(int mangaId,
      [BuildContext? context]);
  Future<List<Fragment$MangaDto>?> searchMangaInSource(
      String sourceId, String query,
      [BuildContext? context]);

  /// Copies library/categories/chapters/tracking from source onto target
  /// WITHOUT removing the source. The bulk runner journals this as its own
  /// boundary before deciding to remove.
  Future<MigrationCopyResult> copyMangaData(
      int fromMangaId, int toMangaId, MigrationOption options,
      [BuildContext? context]);

  /// Removes the source from the library and unbinds any [copiedSourceRecordIds]
  /// locally (never the remote tracker). Idempotent — safe to re-run after a crash.
  Future<({bool success, List<String> warnings})> removeSourceManga(
      int fromMangaId,
      {List<int> copiedSourceRecordIds});

  /// Re-adds a previously-removed source to the library ("Restore source to
  /// library"). Does NOT reverse copied chapters/categories/tracker binds.
  Future<bool> restoreSourceToLibrary(int mangaId);

  /// Preflights migrating [fromMangaId] onto [toMangaId] to detect a merge into
  /// an existing entry and any tracker records that would collide.
  Future<MigrationMergePreflight> preflightMerge(int fromMangaId, int toMangaId);

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
  Future<MigrationCopyResult> copyMangaData(
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
      // Blocks deleting the source so a partial migration can't lose data.
      bool hardFailure = false;

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
            // Fetch itself failed — hard-fail rather than delete having migrated nothing.
            warnings.add(
                'Failed to read source categories: ${sourceCategoriesResult.exception ?? 'no data'}');
            hardFailure = true;
          }
        } catch (e) {
          warnings.add('Category migration failed: $e');
          hardFailure = true;
        }
      }

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

            ChapterState toState(ChapterDto c) => ChapterState(
                  id: c.id,
                  chapterNumber: c.chapterNumber,
                  name: c.name,
                  isRead: c.isRead,
                  isBookmarked: c.isBookmarked,
                  lastPageRead: c.lastPageRead,
                );

            final matchResult = matchChapterState(
              source: sourceChapters.map(toState).toList(),
              target: targetChapters.map(toState).toList(),
            );
            // Unmatched source state can't migrate — must block deleting the source.
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
              // Update chapters one by one to avoid overwhelming the server
              for (final updateInput in chapterUpdates) {
                try {
                  final updateResult = await client.mutate$UpdateChapter(
                    Options$Mutation$UpdateChapter(
                        variables: Variables$Mutation$UpdateChapter(
                            input: updateInput)),
                  );

                  // A null payload (no exception but nothing applied) must not
                  // count as migrated, or the source could be deleted with state unmoved.
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

            if (unmatchedState > 0) {
              warnings.add(
                  '$unmatchedState chapter(s) with read/bookmark/progress had no match on the target (likely different chapter numbering); kept the source so that data is not lost.');
              hardFailure = true;
            }
          } else {
            // Fetch itself failed — hard-fail rather than delete having migrated no progress.
            warnings.add(
                'Failed to read chapters for migration: ${sourceChaptersResult.exception ?? targetChaptersResult.exception ?? 'no data'}');
            hardFailure = true;
          }
        } catch (e) {
          warnings.add('Chapter migration failed: $e');
          hardFailure = true;
        }
      }

      // Uses bindTrackRecord (pure server-DB copy, no external tracker call) when
      // the server supports it, else bindTrack+updateTrack (see
      // TrackerRepository.copyRecord). Copy not move — copied source records get
      // unbound on Migrate (see removeSourceManga).
      int migratedTracking = 0;
      final List<int> copiedSourceRecordIds = [];
      if (options.migrateTracking) {
        try {
          final trackerRepo = TrackerRepository(client);
          final useBindRecord = await trackerRepo.supportsBindTrackRecord();
          final sourceRecords =
              await trackerRepo.getMangaTrackRecords(fromMangaId);
          // Never silently clobber the target's own tracking — keep it unless
          // the owner opted into overwrite.
          final targetRecords =
              await trackerRepo.getMangaTrackRecords(toMangaId) ?? const [];
          final targetTrackerIds = {for (final r in targetRecords) r.trackerId};
          if (sourceRecords != null) {
            for (final record in sourceRecords) {
              if (targetTrackerIds.contains(record.trackerId) &&
                  !options.overwriteExistingTracking) {
                warnings.add(
                    'Kept the target\'s existing tracking for tracker ${record.trackerId}.');
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
                    'Failed to migrate tracking record (tracker ${record.trackerId}): $e');
                hardFailure = true;
              }
            }
          } else {
            // Null result means tracking was never read — hard-fail rather than
            // delete a source whose tracking might not have migrated.
            warnings.add('Failed to read source tracking records.');
            hardFailure = true;
          }
        } catch (e) {
          warnings.add('Tracking migration failed: $e');
          hardFailure = true;
        }
      }

      // Per-manga meta lives server-side as key/value. Rating and tags always
      // carry; reader/display settings ride the toggle. Best-effort — a missing
      // override is not data loss and must never block removal.
      try {
        final mangaRepo = MangaBookRepository(client);
        for (final entry in sourceManga.meta) {
          final carry = _alwaysMetaKeys.contains(entry.key) ||
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

      return MigrationCopyResult(
        success: !hardFailure,
        sourceInLibrary: sourceManga.inLibrary,
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
      return (success: false, warnings: warnings);
    }

    if (copiedSourceRecordIds.isNotEmpty) {
      // Remove the now-duplicate source records. deleteRemoteTrack stays false
      // — never touch the remote AniList/MAL entry.
      final trackerRepo = TrackerRepository(client);
      for (final recordId in copiedSourceRecordIds) {
        try {
          await trackerRepo.unbind(
            recordId: recordId,
            deleteRemoteTrack: false,
          );
        } catch (e) {
          // Stale source record is a cosmetic leftover, not data loss — warn only.
          warnings.add(
              'Migrated tracking, but could not remove the old source record ($recordId): $e');
        }
      }
    }

    return (success: true, warnings: warnings);
  }

  @override
  Future<bool> restoreSourceToLibrary(int mangaId) async {
    final result = await client.mutate$UpdateManga(
      Options$Mutation$UpdateManga(
        variables: Variables$Mutation$UpdateManga(
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
      int fromMangaId, int toMangaId) async {
    final trackerRepo = TrackerRepository(client);
    final targetResult = await client.query$GetManga(
      Options$Query$GetManga(
        variables: Variables$Query$GetManga(id: toMangaId),
      ),
    );
    final targetInLibrary =
        targetResult.parsedData?.manga.inLibrary ?? false;
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
