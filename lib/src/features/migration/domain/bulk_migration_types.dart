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

enum MigrationBlockKind {
  selfTarget,
  sourceChaptersUnavailable,
  targetChaptersUnavailable,
  targetEmpty,
  unmatchedState,
}

enum MigrationFailureKind {
  unsyncedReads,
  copyFailed,
  removalFailed,
}

class MatchOutcome {
  const MatchOutcome({
    this.toMangaId,
    this.toTitle,
    this.toThumbnailUrl,
    this.toSourceName,
    this.toSourceId,
    this.confidence = 0.0,
    this.needsReview = false,
  });

  final int? toMangaId;
  final String? toTitle;
  final String? toThumbnailUrl;
  final String? toSourceName;

  final String? toSourceId;

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
    this.fromSourceId,
    this.fromThumbnailUrl,
    this.fromSourceName,
    this.fromChapterCount = 0,
    this.phase = BulkEntryPhase.queued,
  });

  final int fromMangaId;
  final String fromTitle;

  final String? fromSourceId;
  final String? fromThumbnailUrl;
  final String? fromSourceName;
  final int fromChapterCount;

  double? fromLatestChapter;

  int? toMangaId;
  String? toTitle;
  String? toThumbnailUrl;
  String? toSourceName;

  String? toSourceId;

  /// Duplicate merges may target the origin source; the same entry stays refused.
  bool allowSameSourceTarget = false;
  int toChapterCount = 0;

  // An empty loaded list must remain distinct from an uninspected target.
  bool toChaptersLoaded = false;

  bool targetInspected = false;

  String? toChaptersError;

  bool targetEmpty = false;

  /// Set when the origin chapter list cannot be loaded; blocks migrate, never copy.
  String? fromChaptersError;

  int toUnmatchedState = 0;

  bool get isSelfTarget {
    final toId = toMangaId;
    if (toId == null) return false;
    if (toId == fromMangaId) return true;
    if (allowSameSourceTarget) return false;
    final origin = fromSourceId;
    return origin != null && toSourceId == origin;
  }

  /// Copy keeps the source, so only migrate is blocked.
  bool get blocksMigrate => blockKind != null;

  MigrationBlockKind? get blockKind {
    if (isSelfTarget) return MigrationBlockKind.selfTarget;
    if (toMangaId == null) return null;
    if (fromChaptersError != null) {
      return MigrationBlockKind.sourceChaptersUnavailable;
    }
    if (toChaptersError != null) {
      if (targetEmpty) return MigrationBlockKind.targetEmpty;
      return MigrationBlockKind.targetChaptersUnavailable;
    }
    if (toChaptersLoaded && toChapterCount == 0) {
      return MigrationBlockKind.targetEmpty;
    }
    if (toChaptersLoaded && toUnmatchedState > 0) {
      return MigrationBlockKind.unmatchedState;
    }
    return null;
  }
  double? toLatestChapter;
  double confidence = 0.0;
  BulkEntryPhase phase;
  String? message;

  // Keep failure kinds separate from server text so screens can localize them.
  MigrationFailureKind? failureKind;
  String? failureDetail;
  MigrationCopyResult? copyResult;

  bool targetInLibrary = false;

  /// Colliding target tracker IDs require an explicit keep/overwrite choice.
  Set<int> collidingTrackerIds = const {};

  /// False preserves target tracking; overwrite requires explicit opt-in.
  bool overwriteTracking = false;

  // Retry must reuse this row's mode even if another row runs in a different mode.
  bool? lastDeleteSource;

  int inspectionGeneration = 0;

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
