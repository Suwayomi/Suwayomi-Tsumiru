// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';

import '../domain/bulk_migration_types.dart';
import '../domain/concurrency.dart';
import '../domain/migration_models.dart';
import 'migration_journal.dart';
import 'migration_repository.dart';

/// The headless bulk migration engine: matches, then copies + removes each pair
/// through a durable write-ahead [MigrationJournal] with bounded concurrency, a
/// dirty-state gate, and auth-pause — enforced before source removal, never
/// deferred, so a crash at any point is recoverable via [recover].
class BulkMigrationRunner extends ChangeNotifier {
  BulkMigrationRunner({
    required this.repo,
    required this.journal,
    required this.options,
    required this.matcher,
    required this.dirtyGate,
    required this.isReauthNeeded,
    required this.waitAuthReady,
    required List<BulkMigrationEntry> entries,
    this.onSourceRemoved,
    this.migrateLocalState,
    Semaphore? semaphore,
    RateLimiter? rateLimiter,
    this.autoApplyThreshold = 0.7,
    this.reviewFloor = 0.4,
  })  : _entries = entries,
        semaphore = semaphore ?? Semaphore(3),
        rateLimiter =
            rateLimiter ?? RateLimiter(minInterval: const Duration(milliseconds: 250));

  final MigrationRepository repo;
  final MigrationJournal journal;
  /// Carry-over flags; mutable so the list screen's Settings sheet can amend
  /// them before commit (deleteSource is applied per-commit, not from here).
  MigrationOption options;
  final BulkMatcher matcher;
  final DirtyGate dirtyGate;
  final bool Function() isReauthNeeded;
  final Future<void> Function(CancelToken token) waitAuthReady;

  /// Invoked after a source is removed (Migrate) so offline can evict orphaned
  /// device copies (device ⊆ server). Failures are swallowed — not data loss.
  final Future<void> Function(int fromMangaId)? onSourceRemoved;

  /// Carries device-local state (offline downloads + keep-rule) onto the target,
  /// after a successful copy and before source removal. Best-effort: an offline
  /// copy is never data loss, so a failure must not block the migration.
  final Future<void> Function(
      int fromMangaId, int toMangaId, MigrationOption options)? migrateLocalState;

  final Semaphore semaphore;
  final RateLimiter rateLimiter;

  /// At/above this display-title confidence the target is pre-selected; between
  /// [reviewFloor] and this it is flagged for review; below, it's no match.
  final double autoApplyThreshold;
  final double reviewFloor;

  final List<BulkMigrationEntry> _entries;
  List<BulkMigrationEntry> get entries => List.unmodifiable(_entries);

  CancelToken _token = CancelToken();
  bool get isCancelled => _token.isCancelled;
  bool _paused = false;
  bool get isPaused => _paused;

  void cancel() {
    _token.cancel();
    notifyListeners();
  }

  /// Lets the screen push a repaint after mutating entry display fields
  /// (e.g. fetched chapter counts) outside the runner's own transitions.
  void notify() => notifyListeners();

  void _set(BulkMigrationEntry e, BulkEntryPhase phase, [String? message]) {
    e.phase = phase;
    e.message = message;
    notifyListeners();
  }

  // ---- Matching phase -------------------------------------------------------

  /// Runs the matcher for every un-searched entry through the rate limiter and
  /// concurrency bound. No mutations — populates targets + confidence only.
  Future<void> search() async {
    final work = _entries
        .where((e) => e.phase == BulkEntryPhase.queued)
        .map((e) => semaphore.withPermit(() => _searchOne(e), _token))
        .toList();
    await _settle(work);
  }

  Future<void> _searchOne(BulkMigrationEntry e) async {
    if (_token.isCancelled) return;
    _set(e, BulkEntryPhase.searching);
    try {
      final outcome = await matcher(e, _token);
      e.toMangaId = outcome.toMangaId;
      e.toTitle = outcome.toTitle;
      e.toThumbnailUrl = outcome.toThumbnailUrl;
      e.toSourceName = outcome.toSourceName;
      e.confidence = outcome.confidence;
      if (!outcome.hasMatch) {
        _set(e, BulkEntryPhase.noMatch);
      } else if (outcome.needsReview || outcome.confidence < autoApplyThreshold) {
        _set(e, BulkEntryPhase.needsReview);
      } else {
        _set(e, BulkEntryPhase.ready);
      }
    } on CancelledException {
      // leave queued/searching for a later re-run
    } catch (err) {
      _set(e, BulkEntryPhase.failed, '$err');
    }
  }

  // ---- Merge preflight ------------------------------------------------------

  /// Preflights each matched entry: flags targets already in library and
  /// colliding trackers, so the owner can choose keep vs overwrite. No mutations.
  Future<void> preflight() async {
    final work = _entries
        .where((e) =>
            e.toMangaId != null &&
            (e.phase == BulkEntryPhase.ready ||
                e.phase == BulkEntryPhase.needsReview))
        .map((e) => semaphore.withPermit(() => _preflightOne(e), _token))
        .toList();
    await _settle(work);
  }

  Future<void> _preflightOne(BulkMigrationEntry e) async {
    final toId = e.toMangaId;
    if (toId == null) return;
    try {
      _token.throwIfCancelled();
      final result = await repo.preflightMerge(e.fromMangaId, toId);
      e.targetInLibrary = result.targetInLibrary;
      e.collidingTrackerIds = result.collidingTrackerIds;
      notifyListeners();
    } on CancelledException {
      // best-effort — a missing preflight just defaults to keep-target
    } catch (_) {
      // best-effort
    }
  }

  // ---- Commit phase ---------------------------------------------------------

  /// Copies + (for Migrate) removes every committable entry. An entry is
  /// committable once it's [BulkEntryPhase.ready], or [needsReview] the owner
  /// approved (moved to ready via [approve]).
  /// The effective Copy-vs-Migrate choice for the run; Komikku picks this on the
  /// list screen's top bar (Copy = keep source, Migrate = remove it).
  late bool _deleteSource = options.deleteSource;

  /// [deleteSource] true = Migrate (remove sources), false = Copy (keep them).
  Future<void> commit({required bool deleteSource}) async {
    _deleteSource = deleteSource;
    final work = _entries
        .where((e) => e.phase == BulkEntryPhase.ready && e.toMangaId != null)
        .map((e) => semaphore.withPermit(() => _commitOne(e), _token))
        .toList();
    await _settle(work);
  }

  /// Commit a single entry now (the per-row "Migrate now" / "Copy now" action).
  Future<void> commitOne(int fromMangaId, {required bool deleteSource}) async {
    _deleteSource = deleteSource;
    final e = _byId(fromMangaId);
    if (e == null || e.toMangaId == null) return;
    await semaphore.withPermit(() => _commitOne(e), _token);
  }

  MigrationOption _optionsFor(BulkMigrationEntry e) => options.copyWith(
        deleteSource: _deleteSource,
        overwriteExistingTracking: e.overwriteTracking,
      );

  Future<void> _commitOne(BulkMigrationEntry e) async {
    final toId = e.toMangaId;
    if (toId == null) return;
    try {
      _token.throwIfCancelled();
      // Auth-pause: a 401 wave halts the batch until reauth, instead of failing
      // every remaining entry mid-removal.
      _paused = isReauthNeeded();
      if (_paused) {
        notifyListeners();
        await waitAuthReady(_token);
        _paused = false;
      }
      _token.throwIfCancelled();

      // Dirty-state gate BEFORE any copy — Migrate must never strand an
      // unsynced offline read on a source about to be removed.
      if (_deleteSource) {
        final clean = await dirtyGate(e.fromMangaId, _token);
        if (!clean) {
          _set(e, BulkEntryPhase.dirtyBlocked,
              'Unsynced offline reads — connect and sync, then retry.');
          return;
        }
      }

      await journal.put(MigrationJournalEntry(
        fromMangaId: e.fromMangaId,
        toMangaId: toId,
        state: MigrationPairState.prepared,
        options: _optionsFor(e),
      ));
      await journal.advance(e.fromMangaId, MigrationPairState.copying);
      _set(e, BulkEntryPhase.copying);

      final copy = await repo.copyMangaData(e.fromMangaId, toId, _optionsFor(e));
      e.copyResult = copy;
      if (!copy.success) {
        await journal.advance(e.fromMangaId, MigrationPairState.failed,
            failureReason: copy.warnings.join('; '));
        _set(e, BulkEntryPhase.failed,
            copy.warnings.isNotEmpty ? copy.warnings.first : 'Copy failed');
        return;
      }
      await journal.advance(e.fromMangaId, MigrationPairState.copied,
          copiedSourceRecordIds: copy.copiedSourceRecordIds);

      final localHook = migrateLocalState;
      if (localHook != null) {
        try {
          await localHook(e.fromMangaId, toId, _optionsFor(e));
        } catch (_) {
          // Best-effort — a stranded download re-fetches on the target later.
        }
      }

      if (!_deleteSource || !copy.sourceInLibrary) {
        await journal.removeEntry(e.fromMangaId);
        _set(e, BulkEntryPhase.done);
        return;
      }

      await journal.advance(e.fromMangaId, MigrationPairState.removing);
      _set(e, BulkEntryPhase.removing);
      final removal = await repo.removeSourceManga(e.fromMangaId,
          copiedSourceRecordIds: copy.copiedSourceRecordIds);
      if (!removal.success) {
        await journal.advance(e.fromMangaId, MigrationPairState.failed,
            failureReason: removal.warnings.join('; '));
        _set(e, BulkEntryPhase.failed,
            'Copied to the new source, but removing the old one failed.');
        return;
      }
      await journal.advance(e.fromMangaId, MigrationPairState.removed);
      await journal.removeEntry(e.fromMangaId);
      await _evict(e.fromMangaId);
      _set(e, BulkEntryPhase.done);
    } on CancelledException {
      // Leave the journal at its last write-ahead state; recover() resumes it.
    } catch (err) {
      await journal.advance(e.fromMangaId, MigrationPairState.failed,
          failureReason: '$err');
      _set(e, BulkEntryPhase.failed, '$err');
    }
  }

  // ---- Recovery -------------------------------------------------------------

  /// Reconciles the journal on relaunch (delegates to [recoverMigrationJournal]
  /// so a launch hook can drain a crashed batch without a full runner).
  Future<void> recover() => recoverMigrationJournal(
        repo: repo,
        journal: journal,
        onSourceRemoved: onSourceRemoved,
      );

  /// Best-effort device eviction after a source is removed (device ⊆ server).
  Future<void> _evict(int fromMangaId) async {
    final hook = onSourceRemoved;
    if (hook == null) return;
    try {
      await hook(fromMangaId);
    } catch (_) {
      // A stray on-device copy is not data loss — never fail the migrate on it.
    }
  }

  // ---- Owner actions --------------------------------------------------------

  void approve(int fromMangaId) {
    final e = _byId(fromMangaId);
    if (e != null && e.toMangaId != null) _set(e, BulkEntryPhase.ready);
  }

  void skip(int fromMangaId) {
    final e = _byId(fromMangaId);
    if (e != null) _set(e, BulkEntryPhase.skipped);
  }

  /// Drops an entry from the list (Komikku `removeManga`) — used after a per-row
  /// migrate/copy so the finished row disappears rather than lingering.
  void remove(int fromMangaId) {
    _entries.removeWhere((e) => e.fromMangaId == fromMangaId);
    notifyListeners();
  }

  /// Owner's keep-vs-overwrite choice for an entry whose target already has a
  /// colliding tracker record.
  void setOverwriteTracking(int fromMangaId, bool overwrite) {
    final e = _byId(fromMangaId);
    if (e == null) return;
    e.overwriteTracking = overwrite;
    notifyListeners();
  }

  /// Re-queues a single retryable entry (failed / noMatch / dirtyBlocked) for
  /// another pass; the caller re-runs search()/commit().
  void retryEntry(int fromMangaId) {
    final e = _byId(fromMangaId);
    if (e == null || !e.isRetryable) return;
    if (_token.isCancelled) _token = CancelToken();
    e.phase =
        e.toMangaId == null ? BulkEntryPhase.queued : BulkEntryPhase.ready;
    e.message = null;
    notifyListeners();
  }

  void overrideTarget(int fromMangaId, int toMangaId, String? toTitle) {
    final e = _byId(fromMangaId);
    if (e == null) return;
    e.toMangaId = toMangaId;
    e.toTitle = toTitle;
    e.confidence = 1.0;
    _set(e, BulkEntryPhase.ready);
  }

  /// Re-queues retryable entries (failed / noMatch / needsReview / dirtyBlocked)
  /// for another search + commit pass. Resets the cancel token.
  void retryFailed() {
    _token = CancelToken();
    for (final e in _entries) {
      if (e.isRetryable) {
        e.phase = e.toMangaId == null
            ? BulkEntryPhase.queued
            : BulkEntryPhase.ready;
      }
    }
    notifyListeners();
  }

  /// Re-adds a removed source to the library. Only meaningful after a done
  /// Migrate; does not reverse copied chapters/categories/tracker binds.
  Future<bool> restoreSource(int fromMangaId) =>
      repo.restoreSourceToLibrary(fromMangaId);

  BulkMigrationEntry? _byId(int fromMangaId) {
    for (final e in _entries) {
      if (e.fromMangaId == fromMangaId) return e;
    }
    return null;
  }

  /// Awaits all work; a thrown [CancelledException] from a cancelled permit is
  /// swallowed so cancel() returns cleanly rather than surfacing an error.
  Future<void> _settle(List<Future<void>> work) async {
    for (final f in work) {
      try {
        await f;
      } on CancelledException {
        // expected on cancel
      }
    }
  }
}

/// Drains the crash-recovery journal using each entry's own persisted options.
/// Standalone so it can run at launch as well as via [BulkMigrationRunner.recover]:
///  - `prepared`/`copying` → re-run copy (idempotent), then remove if Migrate;
///  - `copied`/`removing`  → copy proven, so just (re-)remove the source;
///  - `removed`            → stale terminal, drop;
///  - `failed`             → leave for the owner to retry.
/// Never removes a source not proven copied.
Future<void> recoverMigrationJournal({
  required MigrationRepository repo,
  required MigrationJournal journal,
  Future<void> Function(int fromMangaId)? onSourceRemoved,
}) async {
  Future<void> evict(int id) async {
    if (onSourceRemoved == null) return;
    try {
      await onSourceRemoved(id);
    } catch (_) {
      // A stray on-device copy is not data loss — never fail recovery on it.
    }
  }

  Future<void> resume(MigrationJournalEntry entry,
      {required bool redoCopy}) async {
    var copiedRecords = entry.copiedSourceRecordIds;
    try {
      if (redoCopy) {
        await journal.advance(entry.fromMangaId, MigrationPairState.copying);
        final copy = await repo.copyMangaData(
            entry.fromMangaId, entry.toMangaId, entry.options);
        if (!copy.success) {
          await journal.advance(entry.fromMangaId, MigrationPairState.failed,
              failureReason: copy.warnings.join('; '));
          return;
        }
        copiedRecords = copy.copiedSourceRecordIds;
        await journal.advance(entry.fromMangaId, MigrationPairState.copied,
            copiedSourceRecordIds: copiedRecords);
        if (!copy.sourceInLibrary || !entry.deleteSource) {
          await journal.removeEntry(entry.fromMangaId);
          return;
        }
      }
      if (!entry.deleteSource) {
        await journal.removeEntry(entry.fromMangaId);
        return;
      }
      await journal.advance(entry.fromMangaId, MigrationPairState.removing);
      final removal = await repo.removeSourceManga(entry.fromMangaId,
          copiedSourceRecordIds: copiedRecords);
      if (!removal.success) {
        await journal.advance(entry.fromMangaId, MigrationPairState.failed,
            failureReason: removal.warnings.join('; '));
        return;
      }
      await journal.removeEntry(entry.fromMangaId);
      await evict(entry.fromMangaId);
    } catch (err) {
      await journal.advance(entry.fromMangaId, MigrationPairState.failed,
          failureReason: '$err');
    }
  }

  for (final entry in journal.entries()) {
    switch (entry.state) {
      case MigrationPairState.removed:
        await journal.removeEntry(entry.fromMangaId);
      case MigrationPairState.failed:
        break;
      case MigrationPairState.prepared:
      case MigrationPairState.copying:
        await resume(entry, redoCopy: true);
      case MigrationPairState.copied:
      case MigrationPairState.removing:
        await resume(entry, redoCopy: false);
    }
  }
}
