// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';

import '../domain/bulk_migration_types.dart';
import '../domain/chapter_matcher.dart';
import '../domain/concurrency.dart';
import '../domain/migration_models.dart';
import 'migration_journal.dart';
import 'migration_repository.dart';

class _CommitSnapshot {
  const _CommitSnapshot({
    required this.deleteSource,
    required this.options,
    required this.toMangaId,
    required this.inspectionGeneration,
  });

  final bool deleteSource;
  final MigrationOption options;
  final int toMangaId;
  final int inspectionGeneration;
}

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
    this.loadTargetChapters,
    this.loadSourceChapters,
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

  // Optional fetchers let callers without chapter access skip inspection.
  final Future<List<ChapterState>?> Function(int mangaId)? loadTargetChapters;
  final Future<List<ChapterState>?> Function(int mangaId)? loadSourceChapters;

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

  final Set<int> _inFlight = {};

  bool isBusy(int fromMangaId) => _inFlight.contains(fromMangaId);

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

  // Raw errors read like "Exception: ..."; the prefix adds no information.
  String _displayError(Object err) {
    const prefix = 'Exception: ';
    final text = '$err';
    return text.startsWith(prefix) ? text.substring(prefix.length) : text;
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
      e.toSourceId = outcome.toSourceId;
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
      _set(e, BulkEntryPhase.failed, _displayError(err));
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


  Future<void> inspectTarget(int fromMangaId) async {
    final e = _byId(fromMangaId);
    final toId = e?.toMangaId;
    if (e == null || toId == null || e.targetInspected) return;
    if (_token.isCancelled || isSessionCurrent?.call() == false) return;
    final loadTarget = loadTargetChapters;
    final loadSource = loadSourceChapters;
    if (loadTarget == null || loadSource == null) {
      e.targetInspected = true;
      notifyListeners();
      return;
    }
    List<ChapterState>? target;
    try {
      target = await loadTarget(toId);
    } on CancelledException {
      return;
    } catch (err) {
      if (_token.isCancelled || isSessionCurrent?.call() == false) return;
      if (e.toMangaId != toId) return;
      final failure = _displayError(err);
      e.toChaptersError = failure;
      e.targetEmpty = failure.contains('No chapters found');
      e.targetInspected = true;
      notifyListeners();
      return;
    }
    if (_token.isCancelled || isSessionCurrent?.call() == false) return;
    if (e.toMangaId != toId) return;
    e.toChapterCount = target?.length ?? 0;
    e.toLatestChapter =
        latestChapterNumber(target?.map((c) => c.chapterNumber));
    e.toChaptersLoaded = target != null;
    e.toChaptersError = target == null ? 'chapters unavailable' : null;
    List<ChapterState>? source;
    try {
      source = await loadSource(e.fromMangaId);
    } on CancelledException {
      return;
    } catch (err) {
      if (_token.isCancelled || isSessionCurrent?.call() == false) return;
      if (e.toMangaId != toId) return;
      e.fromChaptersError = _displayError(err);
      e.targetInspected = true;
      notifyListeners();
      return;
    }
    if (_token.isCancelled || isSessionCurrent?.call() == false) return;
    if (e.toMangaId != toId) return;
    if (source == null) {
      e.fromChaptersError = 'chapters unavailable';
      e.targetInspected = true;
      notifyListeners();
      return;
    }
    e.fromChaptersError = null;
    e.toUnmatchedState = target == null
        ? 0
        : matchChapterState(source: source, target: target).unmatchedState;
    e.targetInspected = true;
    notifyListeners();
  }

  /// Blocked targets never migrate (progress would be lost); copy may proceed.
  Future<void> commit({required bool deleteSource}) async {
    for (final e in _entries) {
      if (e.toMangaId != null &&
          e.isSelfTarget &&
          e.phase == BulkEntryPhase.ready) {
        e.lastDeleteSource = deleteSource;
        _refuse(e);
      }
    }
    final candidates = _entries.where(isCopyable).toList();
    for (final e in candidates) {
      _inFlight.add(e.fromMangaId);
      e.lastDeleteSource = deleteSource;
    }
    if (candidates.isNotEmpty) notifyListeners();
    try {
      if (deleteSource) {
        for (final e in candidates) {
          if (e.phase != BulkEntryPhase.ready ||
              e.toMangaId == null ||
              e.targetInspected) {
            continue;
          }
          final toId = e.toMangaId;
          await inspectTarget(e.fromMangaId);
          if (!e.targetInspected ||
              e.toMangaId != toId ||
              e.phase != BulkEntryPhase.ready ||
              e.blocksMigrate) {
            _refuse(e);
          }
        }
      }
      final work = candidates
          .where(
            (e) =>
                e.phase == BulkEntryPhase.ready &&
                e.toMangaId != null &&
                !e.isSelfTarget &&
                (!deleteSource || !e.blocksMigrate),
          )
          .map((e) {
            final snapshot = _capture(e, deleteSource);
            return semaphore.withPermit(() async {
              try {
                await _commitOne(e, snapshot);
              } finally {
                _inFlight.remove(e.fromMangaId);
                notifyListeners();
              }
            }, _token);
          })
          .toList();
      await _settle(work);
    } finally {
      var changed = false;
      for (final e in candidates) {
        changed |= _inFlight.remove(e.fromMangaId);
      }
      if (changed) notifyListeners();
    }
  }

  /// Copy keeps the source, so only migrate is refused for blocked targets.
  bool isCopyable(BulkMigrationEntry e) =>
      e.phase == BulkEntryPhase.ready &&
      e.toMangaId != null &&
      !e.isSelfTarget &&
      !_inFlight.contains(e.fromMangaId);

  bool isMigratable(BulkMigrationEntry e) =>
      isCopyable(e) && !e.blocksMigrate;

  Future<void> commitOne(int fromMangaId, {required bool deleteSource}) async {
    final e = _byId(fromMangaId);
    if (e == null || e.toMangaId == null) return;
    if (_inFlight.contains(fromMangaId)) return;
    // A row action is explicit approval of its match.
    if (e.phase == BulkEntryPhase.needsReview) {
      _set(e, BulkEntryPhase.ready);
    }
    _inFlight.add(fromMangaId);
    e.lastDeleteSource = deleteSource;
    notifyListeners();
    try {
      if (e.isSelfTarget) {
        _refuse(e);
        return;
      }
      final toId = e.toMangaId;
      if (deleteSource) {
        if (!e.targetInspected) {
          await inspectTarget(fromMangaId);
        }
        if (!e.targetInspected ||
            e.toMangaId != toId ||
            e.phase != BulkEntryPhase.ready ||
            e.blocksMigrate) {
          _refuse(e);
          return;
        }
      } else if (e.phase != BulkEntryPhase.ready) {
        _refuse(e);
        return;
      }
      final snapshot = _capture(e, deleteSource);
      await semaphore.withPermit(() => _commitOne(e, snapshot), _token);
    } finally {
      _inFlight.remove(fromMangaId);
      notifyListeners();
    }
  }

  void _refuse(BulkMigrationEntry e) {
    e.failureKind = null;
    e.failureDetail = null;
    _set(e, BulkEntryPhase.failed);
  }

  // Pin each row's inputs so concurrent rows cannot change its mode or target.
  _CommitSnapshot _capture(BulkMigrationEntry e, bool deleteSource) {
    e.lastDeleteSource = deleteSource;
    return _CommitSnapshot(
      deleteSource: deleteSource,
      options: options.copyWith(
        deleteSource: deleteSource,
        overwriteExistingTracking: e.overwriteTracking,
      ),
      toMangaId: e.toMangaId!,
      inspectionGeneration: e.inspectionGeneration,
    );
  }

  // Reject queued work if its target or inspection changes before the worker starts.
  bool _snapshotValid(BulkMigrationEntry e, _CommitSnapshot s) {
    if (e.toMangaId != s.toMangaId ||
        e.inspectionGeneration != s.inspectionGeneration) {
      return false;
    }
    if (e.isSelfTarget) return false;
    if (s.deleteSource && (!e.targetInspected || e.blocksMigrate)) return false;
    return true;
  }

  Future<void> _commitOne(BulkMigrationEntry e, _CommitSnapshot s) async {
    final toId = s.toMangaId;
    if (!_snapshotValid(e, s)) {
      _refuse(e);
      return;
    }
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
      if (!_snapshotValid(e, s)) {
        _refuse(e);
        return;
      }

      // Flush unsynced offline reads before copying a source that will be removed.
      if (s.deleteSource) {
        final clean = await dirtyGate(e.fromMangaId, _token);
        _checkActive();
        if (!clean) {
          e.failureKind = MigrationFailureKind.unsyncedReads;
          e.failureDetail = null;
          _set(e, BulkEntryPhase.dirtyBlocked);
          return;
        }
      }

      if (!_snapshotValid(e, s)) {
        _refuse(e);
        return;
      }
      await journal.put(
        MigrationJournalEntry(
          fromMangaId: e.fromMangaId,
          toMangaId: toId,
          state: MigrationPairState.prepared,
          options: s.options,
        ),
      );
      _checkActive();
      await journal.advance(e.fromMangaId, MigrationPairState.copying);
      _checkActive();
      _set(e, BulkEntryPhase.copying);

      final copy = await repo.copyMangaData(e.fromMangaId, toId, s.options);
      _checkActive();
      e.copyResult = copy;
      if (!copy.success) {
        await journal.advance(
          e.fromMangaId,
          MigrationPairState.failed,
          failureReason: copy.warnings.join('; '),
        );
        e.failureKind = MigrationFailureKind.copyFailed;
        e.failureDetail = copy.warnings.isNotEmpty
            ? copy.warnings.join('; ')
            : null;
        _set(e, BulkEntryPhase.failed);
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
          await localHook(e.fromMangaId, toId, s.options);
        } catch (_) {}
      }

      _checkActive();
      if (!s.deleteSource || !copy.sourceInLibrary) {
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
        e.failureKind = MigrationFailureKind.removalFailed;
        e.failureDetail = removal.warnings.isNotEmpty
            ? removal.warnings.join('; ')
            : null;
        _set(e, BulkEntryPhase.failed);
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
      _set(e, BulkEntryPhase.failed, _displayError(err));
    }
  }


  Future<void> recover() => recoverMigrationJournal(
    repo: repo,
    journal: journal,
    dirtyGate: dirtyGate,
    cancelToken: _token,
    migrateLocalState: migrateLocalState,
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
    if (_inFlight.contains(fromMangaId)) return;
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

  Future<void> retryOne(int fromMangaId) async {
    if (_inFlight.contains(fromMangaId)) return;
    final e = _byId(fromMangaId);
    if (e == null || !e.isRetryable) return;
    retryEntry(fromMangaId);
    if (e.toMangaId == null) {
      await semaphore.withPermit(() => _searchOne(e), _token);
    } else {
      await commitOne(fromMangaId, deleteSource: e.lastDeleteSource ?? false);
    }
  }

  /// Requeues failed, unmatched, or dirty-blocked entries; caller reruns search/commit.
  void retryEntry(int fromMangaId) {
    if (_inFlight.contains(fromMangaId)) return;
    final e = _byId(fromMangaId);
    if (e == null || !e.isRetryable) return;
    if (_token.isCancelled) _token = CancelToken();
    _clearInspection(e);
    e.phase = e.toMangaId == null
        ? BulkEntryPhase.queued
        : BulkEntryPhase.ready;
    e.message = null;
    e.failureKind = null;
    e.failureDetail = null;
    notifyListeners();
  }

  void overrideTarget(
    int fromMangaId,
    int toMangaId,
    String? toTitle, {
    String? toThumbnailUrl,
    String? toSourceName,
    String? toSourceId,
    bool allowSameSource = false,
  }) {
    if (_inFlight.contains(fromMangaId)) return;
    final e = _byId(fromMangaId);
    if (e == null) return;
    e.toMangaId = toMangaId;
    e.toTitle = toTitle;
    e.toThumbnailUrl = toThumbnailUrl;
    e.toSourceName = toSourceName;
    e.toSourceId = toSourceId;
    e.allowSameSourceTarget = allowSameSource;
    _clearInspection(e);
    e.confidence = 1.0;
    e.failureKind = null;
    e.failureDetail = null;
    _set(e, BulkEntryPhase.ready);
  }

  void _clearInspection(BulkMigrationEntry e) {
    e.inspectionGeneration++;
    e.targetInspected = false;
    e.toChaptersLoaded = false;
    e.toChapterCount = 0;
    e.toLatestChapter = null;
    e.toChaptersError = null;
    e.targetEmpty = false;
    e.fromChaptersError = null;
    e.toUnmatchedState = 0;
  }

  /// Requeues retryable entries for search/commit and resets cancellation.
  void retryFailed() {
    _token = CancelToken();
    for (final e in _entries) {
      if (e.isRetryable) {
        _clearInspection(e);
        e.phase = e.toMangaId == null
            ? BulkEntryPhase.queued
            : BulkEntryPhase.ready;
      }
    }
    notifyListeners();
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
  DirtyGate? dirtyGate,
  CancelToken? cancelToken,
  Future<void> Function(int fromMangaId, int toMangaId, MigrationOption options)?
  migrateLocalState,
}) async {
  bool current() => isSessionCurrent?.call() ?? true;
  final gateToken = cancelToken ?? CancelToken();
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
        // The journal only proves an earlier copy; reread current progress first.
        if (entry.deleteSource && dirtyGate != null) {
          final clean = await dirtyGate(entry.fromMangaId, gateToken);
          if (!current()) return;
          if (!clean) {
            await journal.advance(
              entry.fromMangaId,
              MigrationPairState.failed,
              failureReason: 'unsynced offline progress',
            );
            return;
          }
        }
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
        final hook = migrateLocalState;
        if (hook != null) {
          try {
            await hook(entry.fromMangaId, entry.toMangaId, entry.options);
          } catch (_) {}
        }
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
        // A removal needs a fresh copy against current state; copy-only clears.
        await resume(entry, redoCopy: entry.deleteSource);
    }
  }
}
