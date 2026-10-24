// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:freezed_annotation/freezed_annotation.dart';

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
    // Preserve target tracker records unless overwrite is explicitly selected.
    @Default(false) bool overwriteExistingTracking,
  }) = _MigrationOption;

  factory MigrationOption.fromJson(Map<String, dynamic> json) =>
      _$MigrationOptionFromJson(json);
}

/// Copy outcome before removal; the runner journals copy and removal separately.
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

  /// Source removal is safe only when no copy step hard-failed.
  final bool success;
  final bool sourceInLibrary;
  final List<String> warnings;
  final int migratedChapters;
  final int migratedCategories;
  final int migratedTracking;

  /// Copied source tracker IDs to unbind locally, never on the remote tracker.
  final List<int> copiedSourceRecordIds;
  final String? targetTitle;
  final String? targetSourceId;
  final String? error;
}

/// Existing-target and tracker collisions requiring a keep/overwrite choice.
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

@freezed
abstract class MigrationRouteData with _$MigrationRouteData {
  const factory MigrationRouteData({
    required Fragment$MangaDto sourceManga,
  }) = _MigrationRouteData;
}

@freezed
abstract class MigrationBulkConfigData with _$MigrationBulkConfigData {
  const factory MigrationBulkConfigData({
    required List<int> mangaIds,
  }) = _MigrationBulkConfigData;
}

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

@freezed
abstract class MigrationSourceMangaData with _$MigrationSourceMangaData {
  const factory MigrationSourceMangaData({
    required String sourceId,
    required String sourceName,
  }) = _MigrationSourceMangaData;
}
