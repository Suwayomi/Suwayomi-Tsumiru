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

/// Journals copy and removal before each server mutation so interrupted batches can recover.
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
    this.isSessionCurrent,
    this.migrateLocalState,
    Semaphore? semaphore,
    RateLimiter? rateLimiter,
    this.autoApplyThreshold = 0.7,
    this.reviewFloor = 0.4,
  }) : _entries = entries,
       semaphore = semaphore ?? Semaphore(3),
       rateLimiter =
           rateLimiter ??
           RateLimiter(minInterval: const Duration(milliseconds: 250));

  final bool Function()? isSessionCurrent;

  void _checkActive() {
    _token.throwIfCancelled();
    if (isSessionCurrent?.call() == false) throw const CancelledException();
  }

  final MigrationRepository repo;
  final MigrationJournal journal;

  /// Mutable until commit; deleteSource is supplied separately per commit.
  MigrationOption options;
  final BulkMatcher matcher;
  final DirtyGate dirtyGate;
  final bool Function() isReauthNeeded;
  final Future<void> Function(CancelToken token) waitAuthReady;

  /// Evicts device copies after source removal; failures do not fail migration.
  final Future<void> Function(int fromMangaId)? onSourceRemoved;

  /// Carries offline state after copy and before removal; failures do not block migration.
  final Future<void> Function(
    int fromMangaId,
    int toMangaId,
    MigrationOption options,
  )?
  migrateLocalState;

  final Semaphore semaphore;
  final RateLimiter rateLimiter;

  /// Scores at this threshold auto-select; [reviewFloor] to here requires review.
  final double autoApplyThreshold;
  final double reviewFloor;

  final List<BulkMigrationEntry> _entries;
  List<BulkMigrationEntry> get entries => List.unmodifiable(_entries);

  CancelToken _token = CancelToken();
  bool get isCancelled =>
      _token.isCancelled || isSessionCurrent?.call() == false;
  bool _paused = false;
  bool get isPaused => _paused;

  void cancel() {
    _token.cancel();
    notifyListeners();
  }

  void notify() => notifyListeners();

  void _set(BulkMigrationEntry e, BulkEntryPhase phase, [String? message]) {
    e.phase = phase;
    e.message = message;
    notifyListeners();
  }


  /// Populates matches and confidence without server mutations.
  Future<void> search() async {
    final work = _entries
        .where((e) => e.phase == BulkEntryPhase.queued)
        .map((e) => semaphore.withPermit(() => _searchOne(e), _token))
        .toList();
    await _settle(work);
  }

  Future<void> _searchOne(BulkMigrationEntry e) async {
    if (_token.isCancelled || isSessionCurrent?.call() == false) return;
    _set(e, BulkEntryPhase.searching);
    try {
      final outcome = await matcher(e, _token);
      _checkActive();
      e.toMangaId = outcome.toMangaId;
      e.toTitle = outcome.toTitle;
      e.toThumbnailUrl = outcome.toThumbnailUrl;
      e.toSourceName = outcome.toSourceName;
      e.confidence = outcome.confidence;
      if (!outcome.hasMatch) {
        _set(e, BulkEntryPhase.noMatch);
      } else if (outcome.needsReview ||
          outcome.confidence < autoApplyThreshold) {
        _set(e, BulkEntryPhase.needsReview);
      } else {
        _set(e, BulkEntryPhase.ready);
      }
    } on CancelledException {
      // Leave queued/searching entries for a later run.
    } catch (err) {
      _set(e, BulkEntryPhase.failed, '$err');
    }
  }


  /// Detects existing targets and tracker collisions without server mutations.
  Future<void> preflight() async {
    final work = _entries
        .where(
          (e) =>
              e.toMangaId != null &&
              (e.phase == BulkEntryPhase.ready ||
                  e.phase == BulkEntryPhase.needsReview),
        )
        .map((e) => semaphore.withPermit(() => _preflightOne(e), _token))
        .toList();
    await _settle(work);
  }

  Future<void> _preflightOne(BulkMigrationEntry e) async {
    final toId = e.toMangaId;
    if (toId == null) return;
    try {
      _checkActive();
      final result = await repo.preflightMerge(e.fromMangaId, toId);
      _checkActive();
      e.targetInLibrary = result.targetInLibrary;
      e.collidingTrackerIds = result.collidingTrackerIds;
      notifyListeners();
    } on CancelledException {
      // Missing preflight preserves target tracking by default.
    } catch (_) {
      // Missing preflight preserves target tracking by default.
    }
  }


  late bool _deleteSource = options.deleteSource;

  /// [deleteSource] removes sources after copy; false keeps them.
  Future<void> commit({required bool deleteSource}) async {
    _deleteSource = deleteSource;
    final work = _entries
        .where((e) => e.phase == BulkEntryPhase.ready && e.toMangaId != null)
        .map((e) => semaphore.withPermit(() => _commitOne(e), _token))
        .toList();
    await _settle(work);
  }

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
      _checkActive();
      // Pause on reauth before processing further entries.
      _paused = isReauthNeeded();
      if (_paused) {
        notifyListeners();
        await waitAuthReady(_token);
        _paused = false;
      }
      _checkActive();

      // Flush unsynced offline reads before copying a source that will be removed.
      if (_deleteSource) {
        final clean = await dirtyGate(e.fromMangaId, _token);
        _checkActive();
        if (!clean) {
          _set(
            e,
            BulkEntryPhase.dirtyBlocked,
            'Unsynced offline reads — connect and sync, then retry.',
          );
          return;
        }
      }

      await journal.put(
        MigrationJournalEntry(
          fromMangaId: e.fromMangaId,
          toMangaId: toId,
          state: MigrationPairState.prepared,
          options: _optionsFor(e),
        ),
      );
      _checkActive();
      await journal.advance(e.fromMangaId, MigrationPairState.copying);
      _checkActive();
      _set(e, BulkEntryPhase.copying);

      final copy = await repo.copyMangaData(
        e.fromMangaId,
        toId,
        _optionsFor(e),
      );
      _checkActive();
      e.copyResult = copy;
      if (!copy.success) {
        await journal.advance(
          e.fromMangaId,
          MigrationPairState.failed,
          failureReason: copy.warnings.join('; '),
        );
        _set(
          e,
          BulkEntryPhase.failed,
          copy.warnings.isNotEmpty ? copy.warnings.first : 'Copy failed',
        );
        return;
      }
      await journal.advance(
        e.fromMangaId,
        MigrationPairState.copied,
        copiedSourceRecordIds: copy.copiedSourceRecordIds,
      );

      _checkActive();
      final localHook = migrateLocalState;
      if (localHook != null) {
        try {
          await localHook(e.fromMangaId, toId, _optionsFor(e));
        } catch (_) {
        }
      }

      _checkActive();
      if (!_deleteSource || !copy.sourceInLibrary) {
        await journal.removeEntry(e.fromMangaId);
        _set(e, BulkEntryPhase.done);
        return;
      }

      await journal.advance(e.fromMangaId, MigrationPairState.removing);
      _checkActive();
      _set(e, BulkEntryPhase.removing);
      final removal = await repo.removeSourceManga(
        e.fromMangaId,
        copiedSourceRecordIds: copy.copiedSourceRecordIds,
      );
      _checkActive();
      if (!removal.success) {
        await journal.advance(
          e.fromMangaId,
          MigrationPairState.failed,
          failureReason: removal.warnings.join('; '),
        );
        _set(
          e,
          BulkEntryPhase.failed,
          'Copied to the new source, but removing the old one failed.',
        );
        return;
      }
      await journal.advance(e.fromMangaId, MigrationPairState.removed);
      _checkActive();
      await journal.removeEntry(e.fromMangaId);
      _checkActive();
      await _evict(e.fromMangaId);
      _set(e, BulkEntryPhase.done);
    } on CancelledException {
      // Keep the last write-ahead state for recovery.
    } catch (err) {
      if (isSessionCurrent?.call() == false || _token.isCancelled) return;
      await journal.advance(
        e.fromMangaId,
        MigrationPairState.failed,
        failureReason: '$err',
      );
      _set(e, BulkEntryPhase.failed, '$err');
    }
  }


  Future<void> recover() => recoverMigrationJournal(
    repo: repo,
    journal: journal,
    onSourceRemoved: onSourceRemoved,
    isSessionCurrent: () =>
        !_token.isCancelled && (isSessionCurrent?.call() ?? true),
  );

  Future<void> _evict(int fromMangaId) async {
    final hook = onSourceRemoved;
    _checkActive();
    if (hook == null) return;
    try {
      await hook(fromMangaId);
    } catch (_) {
      // Eviction failure leaves a spare device copy and must not fail migration.
    }
  }


  void approve(int fromMangaId) {
    final e = _byId(fromMangaId);
    if (e != null && e.toMangaId != null) _set(e, BulkEntryPhase.ready);
  }

  void skip(int fromMangaId) {
    final e = _byId(fromMangaId);
    if (e != null) _set(e, BulkEntryPhase.skipped);
  }

  void remove(int fromMangaId) {
    _entries.removeWhere((e) => e.fromMangaId == fromMangaId);
    notifyListeners();
  }

  void setOverwriteTracking(int fromMangaId, bool overwrite) {
    final e = _byId(fromMangaId);
    if (e == null) return;
    e.overwriteTracking = overwrite;
    notifyListeners();
  }

  /// Requeues failed, unmatched, or dirty-blocked entries; caller reruns search/commit.
  void retryEntry(int fromMangaId) {
    final e = _byId(fromMangaId);
    if (e == null || !e.isRetryable) return;
    if (_token.isCancelled) _token = CancelToken();
    e.phase = e.toMangaId == null
        ? BulkEntryPhase.queued
        : BulkEntryPhase.ready;
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

  /// Requeues retryable entries for search/commit and resets cancellation.
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

  /// Restores library membership only; copied chapters, categories, and tracker bindings remain.
  Future<bool> restoreSource(int fromMangaId) {
    _checkActive();
    return repo.restoreSourceToLibrary(fromMangaId);
  }

  BulkMigrationEntry? _byId(int fromMangaId) {
    for (final e in _entries) {
      if (e.fromMangaId == fromMangaId) return e;
    }
    return null;
  }

  Future<void> _settle(List<Future<void>> work) async {
    for (final f in work) {
      try {
        await f;
      } on CancelledException {
        // Cancellation is an expected completion path.
      }
    }
  }
}

/// Replays interrupted copy/removal states; never removes a source without a completed copy.
Future<void> recoverMigrationJournal({
  required MigrationRepository repo,
  required MigrationJournal journal,
  Future<void> Function(int fromMangaId)? onSourceRemoved,
  bool Function()? isSessionCurrent,
}) async {
  bool current() => isSessionCurrent?.call() ?? true;
  Future<void> evict(int id) async {
    if (!current() || onSourceRemoved == null) return;
    try {
      await onSourceRemoved(id);
    } catch (_) {
      // Eviction failure leaves a spare device copy and must not fail recovery.
    }
  }

  Future<void> resume(
    MigrationJournalEntry entry, {
    required bool redoCopy,
  }) async {
    if (!current()) return;
    var copiedRecords = entry.copiedSourceRecordIds;
    try {
      if (redoCopy) {
        await journal.advance(entry.fromMangaId, MigrationPairState.copying);
        if (!current()) return;
        final copy = await repo.copyMangaData(
          entry.fromMangaId,
          entry.toMangaId,
          entry.options,
        );
        if (!current()) return;
        if (!copy.success) {
          await journal.advance(
            entry.fromMangaId,
            MigrationPairState.failed,
            failureReason: copy.warnings.join('; '),
          );
          return;
        }
        copiedRecords = copy.copiedSourceRecordIds;
        await journal.advance(
          entry.fromMangaId,
          MigrationPairState.copied,
          copiedSourceRecordIds: copiedRecords,
        );
        if (!current()) return;
        if (!copy.sourceInLibrary || !entry.deleteSource) {
          await journal.removeEntry(entry.fromMangaId);
          return;
        }
      }
      if (!current()) return;
      if (!entry.deleteSource) {
        await journal.removeEntry(entry.fromMangaId);
        return;
      }
      await journal.advance(entry.fromMangaId, MigrationPairState.removing);
      if (!current()) return;
      final removal = await repo.removeSourceManga(
        entry.fromMangaId,
        copiedSourceRecordIds: copiedRecords,
      );
      if (!current()) return;
      if (!removal.success) {
        await journal.advance(
          entry.fromMangaId,
          MigrationPairState.failed,
          failureReason: removal.warnings.join('; '),
        );
        return;
      }
      await journal.removeEntry(entry.fromMangaId);
      if (!current()) return;
      await evict(entry.fromMangaId);
    } catch (err) {
      if (!current()) return;
      await journal.advance(
        entry.fromMangaId,
        MigrationPairState.failed,
        failureReason: '$err',
      );
    }
  }

  for (final entry in journal.entries()) {
    if (!current()) return;
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
