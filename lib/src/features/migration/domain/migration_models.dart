// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../browse_center/domain/source/graphql/__generated__/fragment.graphql.dart';
import '../../manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';

part 'migration_models.freezed.dart';
part 'migration_models.g.dart';

@freezed
abstract class MigrationSource with _$MigrationSource {
  const factory MigrationSource({
    required String id,
    required String name,
    required String lang,
    @Default(false) bool isConfigured,
    @Default(0) int mangaCount,
    String? displayName,
    bool? supportsLatest,
  }) = _MigrationSource;

  factory MigrationSource.fromJson(Map<String, dynamic> json) =>
      _$MigrationSourceFromJson(json);
}

@freezed
abstract class MigrationOption with _$MigrationOption {
  const factory MigrationOption({
    @Default(true) bool migrateChapters,
    @Default(true) bool migrateCategories,
    @Default(false) bool migrateDownloads,
    @Default(true) bool migrateReaderSettings,
    @Default(true) bool migrateOfflineSettings,
    @Default(false) bool migrateTracking,
    @Default(true) bool deleteSource,
    // When the target already has a track record for the same tracker, keep the
    // target's by default; overwrite with the source's only on explicit opt-in.
    @Default(false) bool overwriteExistingTracking,
  }) = _MigrationOption;

  factory MigrationOption.fromJson(Map<String, dynamic> json) =>
      _$MigrationOptionFromJson(json);
}

/// Outcome of copying one manga's data (library/categories/chapters/tracking)
/// onto a target, WITHOUT removing the source. Internal to the migration
/// engine — the source-removal step consumes it. Plain class (no serialization)
/// so the bulk runner can journal copy/remove as separate boundaries.
class MigrationCopyResult {
  const MigrationCopyResult({
    required this.success,
    required this.sourceInLibrary,
    this.warnings = const [],
    this.migratedChapters = 0,
    this.migratedCategories = 0,
    this.migratedTracking = 0,
    this.copiedSourceRecordIds = const [],
    this.targetTitle,
    this.targetSourceId,
    this.error,
  });

  /// True when no step hard-failed — only then is removing the source safe.
  final bool success;
  final bool sourceInLibrary;
  final List<String> warnings;
  final int migratedChapters;
  final int migratedCategories;
  final int migratedTracking;

  /// Source track-record ids that were copied to the target; on a Migrate these
  /// are unbound from the source (locally, never touching the remote tracker).
  final List<int> copiedSourceRecordIds;
  final String? targetTitle;
  final String? targetSourceId;
  final String? error;
}

/// Preflight of migrating onto a specific target: whether the target is already
/// a library entry, and which trackers already have a record there that the
/// source would collide with. Drives the merge keep-vs-overwrite choice.
class MigrationMergePreflight {
  const MigrationMergePreflight({
    required this.targetInLibrary,
    this.collidingTrackerIds = const {},
  });

  final bool targetInLibrary;
  final Set<int> collidingTrackerIds;

  bool get hasTrackerCollision => collidingTrackerIds.isNotEmpty;
}

@freezed
abstract class MangaSearchResult with _$MangaSearchResult {
  const factory MangaSearchResult({
    required Fragment$MangaDto manga,
    @Default(0.0) double similarity,
    String? matchReason,
  }) = _MangaSearchResult;

  factory MangaSearchResult.fromJson(Map<String, dynamic> json) =>
      _$MangaSearchResultFromJson(json);
}

// Nav route data classes — no JSON serialization needed, navigation-only.
@freezed
abstract class MigrationRouteData with _$MigrationRouteData {
  const factory MigrationRouteData({
    required Fragment$MangaDto sourceManga,
  }) = _MigrationRouteData;
}

/// Nav payload for the bulk config screen — the set of library manga to migrate.
@freezed
abstract class MigrationBulkConfigData with _$MigrationBulkConfigData {
  const factory MigrationBulkConfigData({
    required List<int> mangaIds,
  }) = _MigrationBulkConfigData;
}

/// Nav payload for the bulk run screen — the configured batch, ready to search
/// and commit.
@freezed
abstract class MigrationBulkRunData with _$MigrationBulkRunData {
  const factory MigrationBulkRunData({
    required List<int> mangaIds,
    required List<String> targetSourceIds,
    required MigrationOption options,
    @Default(false) bool hideUnmatched,
    @Default(false) bool hideWithoutUpdates,
    String? extraSearchQuery,
  }) = _MigrationBulkRunData;
}

/// Nav payload for the per-source picker (Screen 2).
@freezed
abstract class MigrationSourceMangaData with _$MigrationSourceMangaData {
  const factory MigrationSourceMangaData({
    required String sourceId,
    required String sourceName,
  }) = _MigrationSourceMangaData;
}
