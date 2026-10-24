// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

library;

import 'concurrency.dart';
import 'migration_models.dart';

typedef BulkMatcher = Future<MatchOutcome> Function(
    BulkMigrationEntry entry, CancelToken token);

/// Flushes unsynced offline reads; true requires a clean, reachable source before removal.
typedef DirtyGate = Future<bool> Function(int mangaId, CancelToken token);

enum BulkEntryPhase {
  queued,

  searching,

  ready,

  /// Requires confirmation before migration.
  needsReview,

  noMatch,

  /// Source is unreachable or has unsynced reads; removal must wait.
  dirtyBlocked,

  copying,

  /// Source removal occurs only in Migrate mode.
  removing,

  done,

  /// Retryable failure; the source remains intact.
  failed,

  skipped,
}

class MatchOutcome {
  const MatchOutcome({
    this.toMangaId,
    this.toTitle,
    this.toThumbnailUrl,
    this.toSourceName,
    this.confidence = 0.0,
    this.needsReview = false,
  });

  final int? toMangaId;
  final String? toTitle;
  final String? toThumbnailUrl;
  final String? toSourceName;

  /// Normalized display-title similarity in [0, 1].
  final double confidence;

  /// Review-band match is preselected but requires approval.
  final bool needsReview;

  bool get hasMatch => toMangaId != null;
}

/// Mutable entry; the runner advances phase in place and notifies listeners.
class BulkMigrationEntry {
  BulkMigrationEntry({
    required this.fromMangaId,
    required this.fromTitle,
    this.fromThumbnailUrl,
    this.fromSourceName,
    this.fromChapterCount = 0,
    this.phase = BulkEntryPhase.queued,
  });

  final int fromMangaId;
  final String fromTitle;

  final String? fromThumbnailUrl;
  final String? fromSourceName;
  final int fromChapterCount;

  double? fromLatestChapter;

  int? toMangaId;
  String? toTitle;
  String? toThumbnailUrl;
  String? toSourceName;
  int toChapterCount = 0;
  double? toLatestChapter;
  double confidence = 0.0;
  BulkEntryPhase phase;
  String? message;
  MigrationCopyResult? copyResult;

  bool targetInLibrary = false;

  /// Colliding target tracker IDs require an explicit keep/overwrite choice.
  Set<int> collidingTrackerIds = const {};

  /// False preserves target tracking; overwrite requires explicit opt-in.
  bool overwriteTracking = false;

  bool get hasTrackerCollision => collidingTrackerIds.isNotEmpty;

  bool get isTerminal =>
      phase == BulkEntryPhase.done ||
      phase == BulkEntryPhase.skipped ||
      phase == BulkEntryPhase.noMatch;

  bool get isRetryable =>
      phase == BulkEntryPhase.failed ||
      phase == BulkEntryPhase.noMatch ||
      phase == BulkEntryPhase.needsReview ||
      phase == BulkEntryPhase.dirtyBlocked;
}
