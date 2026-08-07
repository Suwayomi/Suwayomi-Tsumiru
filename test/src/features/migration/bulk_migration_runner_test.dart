// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/migration/data/bulk_migration_runner.dart';
import 'package:tsumiru/src/features/migration/data/migration_journal.dart';
import 'package:tsumiru/src/features/migration/data/migration_repository.dart';
import 'package:tsumiru/src/features/migration/domain/bulk_migration_types.dart';
import 'package:tsumiru/src/features/migration/domain/concurrency.dart';
import 'package:tsumiru/src/features/migration/domain/migration_models.dart';

/// Controllable fake — records copy/remove calls and can be told to fail.
class FakeMigrationRepository implements MigrationRepository {
  final List<int> copyCalls = [];
  final List<int> removeCalls = [];
  final List<int> restoreCalls = [];

  /// Records the overwrite flag each copy was called with, keyed by fromMangaId.
  final Map<int, bool> copyOverwriteFlags = {};

  /// fromMangaId → number of times to fail copy before succeeding.
  final Map<int, int> copyFailuresRemaining;
  final Set<int> removeShouldFail;
  final bool sourceInLibrary;

  /// fromMangaId → preflight result to return.
  final Map<int, MigrationMergePreflight> preflights;

  FakeMigrationRepository({
    Map<int, int>? copyFailuresRemaining,
    Set<int>? removeShouldFail,
    Map<int, MigrationMergePreflight>? preflights,
    this.sourceInLibrary = true,
  })  : copyFailuresRemaining = copyFailuresRemaining ?? {},
        removeShouldFail = removeShouldFail ?? {},
        preflights = preflights ?? {};

  @override
  Future<MigrationMergePreflight> preflightMerge(
          int fromMangaId, int toMangaId) async =>
      preflights[fromMangaId] ??
      const MigrationMergePreflight(targetInLibrary: false);

  @override
  Future<MigrationCopyResult> copyMangaData(
      int fromMangaId, int toMangaId, MigrationOption options,
      [BuildContext? context]) async {
    copyCalls.add(fromMangaId);
    copyOverwriteFlags[fromMangaId] = options.overwriteExistingTracking;
    final remaining = copyFailuresRemaining[fromMangaId] ?? 0;
    if (remaining > 0) {
      copyFailuresRemaining[fromMangaId] = remaining - 1;
      return MigrationCopyResult(
          success: false,
          sourceInLibrary: sourceInLibrary,
          warnings: const ['simulated copy failure']);
    }
    return MigrationCopyResult(
      success: true,
      sourceInLibrary: sourceInLibrary,
      migratedChapters: 3,
      copiedSourceRecordIds: const [700],
    );
  }

  @override
  Future<({bool success, List<String> warnings})> removeSourceManga(
      int fromMangaId,
      {List<int> copiedSourceRecordIds = const []}) async {
    removeCalls.add(fromMangaId);
    if (removeShouldFail.contains(fromMangaId)) {
      return (success: false, warnings: const ['simulated remove failure']);
    }
    return (success: true, warnings: const <String>[]);
  }

  @override
  Future<bool> restoreSourceToLibrary(int mangaId) async {
    restoreCalls.add(mangaId);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');

  @override
  Future<void> cancelMigration() async {}
}

BulkMigrationEntry entry(int from, {int? to}) {
  final e = BulkMigrationEntry(fromMangaId: from, fromTitle: 'M$from');
  if (to != null) {
    e.toMangaId = to;
    e.toTitle = 'T$to';
    e.confidence = 1.0;
    e.phase = BulkEntryPhase.ready;
  }
  return e;
}

BulkMigrationRunner makeRunner({
  required FakeMigrationRepository repo,
  required MigrationJournal journal,
  required List<BulkMigrationEntry> entries,
  MigrationOption options = const MigrationOption(),
  DirtyGate? dirtyGate,
  bool Function()? isReauthNeeded,
  Future<void> Function(CancelToken)? waitAuthReady,
  BulkMatcher? matcher,
  Future<void> Function(int)? onSourceRemoved,
}) =>
    BulkMigrationRunner(
      repo: repo,
      journal: journal,
      options: options,
      entries: entries,
      matcher: matcher ??
          (e, t) async => MatchOutcome(toMangaId: e.toMangaId, confidence: 1.0),
      dirtyGate: dirtyGate ?? (id, t) async => true,
      isReauthNeeded: isReauthNeeded ?? () => false,
      waitAuthReady: waitAuthReady ?? (t) async {},
      onSourceRemoved: onSourceRemoved,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MigrationJournal journal;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    journal = MigrationJournal(await SharedPreferences.getInstance());
  });

  group('journal', () {
    test('round-trips entries through persistence', () async {
      await journal.put(const MigrationJournalEntry(
        fromMangaId: 1,
        toMangaId: 2,
        state: MigrationPairState.copied,
        options: const MigrationOption(deleteSource: true),
        copiedSourceRecordIds: [700],
      ));
      final reloaded =
          MigrationJournal(await SharedPreferences.getInstance());
      final e = reloaded.entryFor(1)!;
      expect(e.toMangaId, 2);
      expect(e.state, MigrationPairState.copied);
      expect(e.copiedSourceRecordIds, [700]);
    });
  });

  group('commit — Migrate', () {
    test('copies then removes, marks done, clears journal', () async {
      final repo = FakeMigrationRepository();
      final runner = makeRunner(
          repo: repo, journal: journal, entries: [entry(1, to: 100)]);
      await runner.commit(deleteSource: true);
      expect(runner.entries.single.phase, BulkEntryPhase.done);
      expect(repo.copyCalls, [1]);
      expect(repo.removeCalls, [1]);
      expect(journal.entries(), isEmpty);
    });

    test('copy failure keeps the source and does NOT remove', () async {
      final repo =
          FakeMigrationRepository(copyFailuresRemaining: {1: 1});
      final runner = makeRunner(
          repo: repo, journal: journal, entries: [entry(1, to: 100)]);
      await runner.commit(deleteSource: true);
      expect(runner.entries.single.phase, BulkEntryPhase.failed);
      expect(repo.removeCalls, isEmpty);
      expect(journal.entryFor(1)!.state, MigrationPairState.failed);
    });

    test('remove failure leaves the entry failed after a successful copy',
        () async {
      final repo = FakeMigrationRepository(removeShouldFail: {1});
      final runner = makeRunner(
          repo: repo, journal: journal, entries: [entry(1, to: 100)]);
      await runner.commit(deleteSource: true);
      expect(runner.entries.single.phase, BulkEntryPhase.failed);
      expect(repo.copyCalls, [1]);
      expect(repo.removeCalls, [1]);
      expect(journal.entryFor(1)!.state, MigrationPairState.failed);
    });

    test('commitOne then remove drops the row, emptying the list', () async {
      final repo = FakeMigrationRepository();
      final runner = makeRunner(
          repo: repo,
          journal: journal,
          entries: [entry(1, to: 100), entry(2, to: 200)]);
      await runner.commitOne(1, deleteSource: true);
      runner.remove(1);
      expect(runner.entries.map((e) => e.fromMangaId), [2]);
      await runner.commitOne(2, deleteSource: true);
      runner.remove(2);
      expect(runner.entries, isEmpty);
    });
  });

  group('commit — Copy (deleteSource false)', () {
    test('copies but never removes', () async {
      final repo = FakeMigrationRepository();
      final runner = makeRunner(
          repo: repo,
          journal: journal,
          entries: [entry(1, to: 100)],
          options: const MigrationOption(deleteSource: false));
      await runner.commit(deleteSource: false);
      expect(runner.entries.single.phase, BulkEntryPhase.done);
      expect(repo.removeCalls, isEmpty);
      expect(journal.entries(), isEmpty);
    });
  });

  group('dirty-state gate', () {
    test('blocks removal when the source is dirty', () async {
      final repo = FakeMigrationRepository();
      final runner = makeRunner(
        repo: repo,
        journal: journal,
        entries: [entry(1, to: 100)],
        dirtyGate: (id, t) async => false,
      );
      await runner.commit(deleteSource: true);
      expect(runner.entries.single.phase, BulkEntryPhase.dirtyBlocked);
      expect(repo.copyCalls, isEmpty);
      expect(repo.removeCalls, isEmpty);
    });
  });

  group('auth-pause', () {
    test('waits for reauth before committing', () async {
      final repo = FakeMigrationRepository();
      var waited = false;
      var needsAuth = true;
      final runner = makeRunner(
        repo: repo,
        journal: journal,
        entries: [entry(1, to: 100)],
        isReauthNeeded: () => needsAuth,
        waitAuthReady: (t) async {
          waited = true;
          needsAuth = false;
        },
      );
      await runner.commit(deleteSource: true);
      expect(waited, isTrue);
      expect(runner.entries.single.phase, BulkEntryPhase.done);
    });
  });

  group('recovery (simulated mid-batch kill)', () {
    test('copied → resume removes the source, no duplicate copy', () async {
      // Journal says copy already completed but source not yet removed.
      await journal.put(const MigrationJournalEntry(
        fromMangaId: 1,
        toMangaId: 100,
        state: MigrationPairState.copied,
        options: const MigrationOption(deleteSource: true),
        copiedSourceRecordIds: [700],
      ));
      final repo = FakeMigrationRepository();
      final runner =
          makeRunner(repo: repo, journal: journal, entries: []);
      await runner.recover();
      expect(repo.copyCalls, isEmpty, reason: 'copy already proven — no redo');
      expect(repo.removeCalls, [1]);
      expect(journal.entries(), isEmpty);
    });

    test('copying → resume re-runs copy (idempotent) then removes', () async {
      await journal.put(const MigrationJournalEntry(
        fromMangaId: 1,
        toMangaId: 100,
        state: MigrationPairState.copying,
        options: const MigrationOption(deleteSource: true),
      ));
      final repo = FakeMigrationRepository();
      final runner =
          makeRunner(repo: repo, journal: journal, entries: []);
      await runner.recover();
      expect(repo.copyCalls, [1], reason: 'copy not proven — redo it');
      expect(repo.removeCalls, [1]);
      expect(journal.entries(), isEmpty);
    });

    test('failed → left for retry, never removed', () async {
      await journal.put(const MigrationJournalEntry(
        fromMangaId: 1,
        toMangaId: 100,
        state: MigrationPairState.failed,
        options: const MigrationOption(deleteSource: true),
      ));
      final repo = FakeMigrationRepository();
      final runner =
          makeRunner(repo: repo, journal: journal, entries: []);
      await runner.recover();
      expect(repo.removeCalls, isEmpty);
      expect(journal.entryFor(1)!.state, MigrationPairState.failed);
    });
  });

  group('concurrency + cancel', () {
    test('never runs more than 3 copies at once', () async {
      var active = 0;
      var peak = 0;
      final gate = Completer<void>();
      final repo = _GatedRepo(onCopy: () async {
        active++;
        peak = active > peak ? active : peak;
        await gate.future;
        active--;
      });
      final entries = List.generate(8, (i) => entry(i, to: 100 + i));
      final runner = makeRunner(repo: repo, journal: journal, entries: entries);
      final fut = runner.commit(deleteSource: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(peak, 3);
      gate.complete();
      await fut;
      expect(peak, 3);
    });

    test('cancel stops further entries', () async {
      final repo = FakeMigrationRepository();
      final entries = List.generate(6, (i) => entry(i, to: 100 + i));
      final runner = makeRunner(repo: repo, journal: journal, entries: entries);
      runner.cancel();
      await runner.commit(deleteSource: true);
      // Nothing should have been copied — the token was already cancelled.
      expect(repo.copyCalls, isEmpty);
    });
  });

  group('retry', () {
    test('re-queues failed entries and succeeds on the next pass', () async {
      final repo = FakeMigrationRepository(copyFailuresRemaining: {1: 1});
      final runner = makeRunner(
          repo: repo, journal: journal, entries: [entry(1, to: 100)]);
      await runner.commit(deleteSource: true);
      expect(runner.entries.single.phase, BulkEntryPhase.failed);
      runner.retryFailed();
      await runner.commit(deleteSource: true);
      expect(runner.entries.single.phase, BulkEntryPhase.done);
      expect(repo.removeCalls, [1]);
    });

    test('retryEntry re-queues just one entry', () async {
      final repo = FakeMigrationRepository(copyFailuresRemaining: {1: 1});
      final runner = makeRunner(
          repo: repo, journal: journal, entries: [entry(1, to: 100)]);
      await runner.commit(deleteSource: true);
      expect(runner.entries.single.phase, BulkEntryPhase.failed);
      runner.retryEntry(1);
      expect(runner.entries.single.phase, BulkEntryPhase.ready);
      await runner.commit(deleteSource: true);
      expect(runner.entries.single.phase, BulkEntryPhase.done);
    });
  });

  group('merge preflight + tracker-collision policy', () {
    test('preflight populates targetInLibrary and colliding trackers', () async {
      final repo = FakeMigrationRepository(preflights: {
        1: const MigrationMergePreflight(
            targetInLibrary: true, collidingTrackerIds: {10}),
      });
      final runner = makeRunner(
          repo: repo, journal: journal, entries: [entry(1, to: 100)]);
      await runner.preflight();
      final e = runner.entries.single;
      expect(e.targetInLibrary, isTrue);
      expect(e.hasTrackerCollision, isTrue);
      expect(e.collidingTrackerIds, {10});
    });

    test('copy defaults to keep-target (overwrite flag false)', () async {
      final repo = FakeMigrationRepository();
      final runner = makeRunner(
          repo: repo, journal: journal, entries: [entry(1, to: 100)]);
      await runner.commit(deleteSource: true);
      expect(repo.copyOverwriteFlags[1], isFalse);
    });

    test('owner opting into overwrite threads the flag into the copy', () async {
      final repo = FakeMigrationRepository();
      final runner = makeRunner(
          repo: repo, journal: journal, entries: [entry(1, to: 100)]);
      runner.setOverwriteTracking(1, true);
      await runner.commit(deleteSource: true);
      expect(repo.copyOverwriteFlags[1], isTrue);
    });
  });

  group('launch recovery (standalone, no runner)', () {
    test('recoverMigrationJournal drains a copied entry by removing the source',
        () async {
      await journal.put(const MigrationJournalEntry(
        fromMangaId: 1,
        toMangaId: 100,
        state: MigrationPairState.copied,
        options: MigrationOption(deleteSource: true),
        copiedSourceRecordIds: [700],
      ));
      final repo = FakeMigrationRepository();
      await recoverMigrationJournal(repo: repo, journal: journal);
      expect(repo.copyCalls, isEmpty);
      expect(repo.removeCalls, [1]);
      expect(journal.entries(), isEmpty);
    });

    test('recovery re-copies with the entry\'s persisted options', () async {
      // Persisted overwrite choice must survive a crash, not revert to keep.
      await journal.put(const MigrationJournalEntry(
        fromMangaId: 1,
        toMangaId: 100,
        state: MigrationPairState.copying,
        options: MigrationOption(deleteSource: true, overwriteExistingTracking: true),
      ));
      final repo = FakeMigrationRepository();
      await recoverMigrationJournal(repo: repo, journal: journal);
      expect(repo.copyOverwriteFlags[1], isTrue);
      expect(repo.removeCalls, [1]);
    });

    test('journal persists the full options across reload', () async {
      await journal.put(const MigrationJournalEntry(
        fromMangaId: 5,
        toMangaId: 50,
        state: MigrationPairState.prepared,
        options: MigrationOption(
            deleteSource: false, migrateTracking: true, overwriteExistingTracking: true),
      ));
      final reloaded = MigrationJournal(await SharedPreferences.getInstance());
      final opts = reloaded.entryFor(5)!.options;
      expect(opts.deleteSource, isFalse);
      expect(opts.migrateTracking, isTrue);
      expect(opts.overwriteExistingTracking, isTrue);
    });
  });

  group('device eviction on move', () {
    test('onSourceRemoved fires after a successful Migrate removal', () async {
      final evicted = <int>[];
      final repo = FakeMigrationRepository();
      final runner = makeRunner(
        repo: repo,
        journal: journal,
        entries: [entry(1, to: 100)],
        onSourceRemoved: (id) async => evicted.add(id),
      );
      await runner.commit(deleteSource: true);
      expect(evicted, [1]);
    });

    test('no eviction on Copy (source not removed)', () async {
      final evicted = <int>[];
      final repo = FakeMigrationRepository();
      final runner = makeRunner(
        repo: repo,
        journal: journal,
        entries: [entry(1, to: 100)],
        options: const MigrationOption(deleteSource: false),
        onSourceRemoved: (id) async => evicted.add(id),
      );
      await runner.commit(deleteSource: false);
      expect(evicted, isEmpty);
    });
  });
}

/// Repo whose copy runs a supplied gate, for concurrency timing.
class _GatedRepo extends FakeMigrationRepository {
  _GatedRepo({required this.onCopy});
  final Future<void> Function() onCopy;

  @override
  Future<MigrationCopyResult> copyMangaData(
      int fromMangaId, int toMangaId, MigrationOption options,
      [BuildContext? context]) async {
    copyCalls.add(fromMangaId);
    await onCopy();
    return const MigrationCopyResult(success: true, sourceInLibrary: true);
  }
}
