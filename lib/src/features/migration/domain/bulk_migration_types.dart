// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// In-memory, UI-facing state for the bulk migration runner. Distinct from the
/// on-disk journal (crash recovery) — this drives the batch screen.
library;

import 'concurrency.dart';
import 'migration_models.dart';

/// Finds a target for one source, through the runner's rate limiter.
typedef BulkMatcher = Future<MatchOutcome> Function(
    BulkMigrationEntry entry, CancelToken token);

/// Flushes a source's unsynced offline reads and reports whether it's now safe
/// to remove (clean + reachable). Injected so the offline specifics live in the
/// providers layer (Phase 7), keeping the runner unit-testable.
typedef DirtyGate = Future<bool> Function(int mangaId, CancelToken token);

/// Where one entry sits in the runner pipeline. Grouped by the batch summary as:
/// review-needed ([needsReview]/[noMatch]), in-flight, done, or [failed].
enum BulkEntryPhase {
  /// Queued, not yet searched.
  queued,

  /// Matcher running against priority sources.
  searching,

  /// Matched with enough confidence to pre-select the target.
  ready,

  /// Matched but low-confidence — the owner must confirm before it migrates.
  needsReview,

  /// No candidate found on any target source.
  noMatch,

  /// Blocked: the source has unsynced offline reads (or is offline) — can't
  /// safely remove until flushed.
  dirtyBlocked,

  /// Copying data onto the target.
  copying,

  /// Removing the source (Migrate only).
  removing,

  /// Migrated/copied successfully.
  done,

  /// A step failed; source kept. Retryable.
  failed,

  /// The owner skipped this entry.
  skipped,
}

/// Result of matching one source against the target sources.
class MatchOutcome {
  const MatchOutcome({
    this.toMangaId,
    this.toTitle,
    this.toThumbnailUrl,
    this.toSourceName,
    this.confidence = 0.0,
    this.needsReview = false,
  });

  /// Chosen target manga id, or null for no match.
  final int? toMangaId;
  final String? toTitle;
  final String? toThumbnailUrl;
  final String? toSourceName;

  /// 0..1 normalized similarity of the display-title match.
  final double confidence;

  /// True when the score is in the review band — pre-selected but not auto-run.
  final bool needsReview;

  bool get hasMatch => toMangaId != null;
}

/// One row in the batch. Mutable — the runner advances [phase] in place and
/// notifies listeners.
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

  // Source card display (from the library entry).
  final String? fromThumbnailUrl;
  final String? fromSourceName;
  final int fromChapterCount;

  /// Highest recognized source chapter number, for the "Latest chapter" line.
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

  /// Merge preflight: the target is already a library entry.
  bool targetInLibrary = false;

  /// Trackers where the target already has a record the source would collide
  /// with. Non-empty means the owner must choose keep vs overwrite.
  Set<int> collidingTrackerIds = const {};

  /// Owner's choice for this entry's tracker collision — overwrite the target's
  /// tracking with the source's. Defaults to keep (false).
  bool overwriteTracking = false;

  bool get hasTrackerCollision => collidingTrackerIds.isNotEmpty;

  bool get isTerminal =>
      phase == BulkEntryPhase.done ||
      phase == BulkEntryPhase.skipped ||
      phase == BulkEntryPhase.noMatch;

  /// Retry re-queues failures and unresolved matches.
  bool get isRetryable =>
      phase == BulkEntryPhase.failed ||
      phase == BulkEntryPhase.noMatch ||
      phase == BulkEntryPhase.needsReview ||
      phase == BulkEntryPhase.dirtyBlocked;
}
