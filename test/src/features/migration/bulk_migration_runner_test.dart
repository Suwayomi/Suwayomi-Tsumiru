// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
  }) : copyFailuresRemaining = copyFailuresRemaining ?? {},
       removeShouldFail = removeShouldFail ?? {},
       preflights = preflights ?? {};

  @override
  Future<MigrationMergePreflight> preflightMerge(
    int fromMangaId,
    int toMangaId,
  ) async =>
      preflights[fromMangaId] ??
      const MigrationMergePreflight(targetInLibrary: false);

  @override
  Future<MigrationCopyResult> copyMangaData(
    int fromMangaId,
    int toMangaId,
    MigrationOption options, [
    BuildContext? context,
  ]) async {
    copyCalls.add(fromMangaId);
    copyOverwriteFlags[fromMangaId] = options.overwriteExistingTracking;
    final remaining = copyFailuresRemaining[fromMangaId] ?? 0;
    if (remaining > 0) {
      copyFailuresRemaining[fromMangaId] = remaining - 1;
      return MigrationCopyResult(
        success: false,
        sourceInLibrary: sourceInLibrary,
        warnings: const ['simulated copy failure'],
      );
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
    int fromMangaId, {
    List<int> copiedSourceRecordIds = const [],
  }) async {
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
  bool Function()? isSessionCurrent,
  Future<void> Function(int, int, MigrationOption)? migrateLocalState,
  bool Function()? isReauthNeeded,
  Future<void> Function(CancelToken)? waitAuthReady,
  BulkMatcher? matcher,
  Future<void> Function(int)? onSourceRemoved,
}) => BulkMigrationRunner(
  repo: repo,
  journal: journal,
  isSessionCurrent: isSessionCurrent,
  migrateLocalState: migrateLocalState,
  options: options,
  entries: entries,
  matcher:
      matcher ??
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

  test(
    'account journals survive restart without adopting another account or legacy data',
    () async {
      final prefs = await SharedPreferences.getInstance();
      const entry = MigrationJournalEntry(
        fromMangaId: 1,
        toMangaId: 2,
        state: MigrationPairState.copying,
        options: MigrationOption(),
      );
      await journal.put(entry);
      final legacy = prefs.getString(MigrationJournal.prefsKey);
      final first = MigrationJournal(prefs, accountId: 'account-a');
      final second = MigrationJournal(prefs, accountId: 'account-b');
      expect(first.entries(), isEmpty);
      expect(second.entries(), isEmpty);
      await first.put(entry);
      await second.put(entry.copyWith(state: MigrationPairState.copied));
      expect(
        MigrationJournal(prefs, accountId: 'account-a').entryFor(1)!.state,
        MigrationPairState.copying,
      );
      expect(
        MigrationJournal(prefs, accountId: 'account-b').entryFor(1)!.state,
        MigrationPairState.copied,
      );
      expect(prefs.getString(MigrationJournal.prefsKey), legacy);
    },
  );

  group('commit — Migrate', () {
    test('copies then removes, marks done, clears journal', () async {
      final repo = FakeMigrationRepository();
      final runner = makeRunner(
        repo: repo,
        journal: journal,
        entries: [entry(1, to: 100)],
      );
      await runner.commit(deleteSource: true);
      expect(runner.entries.single.phase, BulkEntryPhase.done);
      expect(repo.copyCalls, [1]);
      expect(repo.removeCalls, [1]);
      expect(journal.entries(), isEmpty);
    });

    test('copy failure keeps the source and does NOT remove', () async {
      final repo = FakeMigrationRepository(copyFailuresRemaining: {1: 1});
      final runner = makeRunner(
        repo: repo,
        journal: journal,
        entries: [entry(1, to: 100)],
      );
      await runner.commit(deleteSource: true);
      expect(runner.entries.single.phase, BulkEntryPhase.failed);
      expect(repo.removeCalls, isEmpty);
      expect(journal.entryFor(1)!.state, MigrationPairState.failed);
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

  group('recovery (simulated mid-batch kill)', () {
    test('copied → resume removes the source, no duplicate copy', () async {
      // Journal says copy already completed but source not yet removed.
      await journal.put(
        const MigrationJournalEntry(
          fromMangaId: 1,
          toMangaId: 100,
          state: MigrationPairState.copied,
          options: MigrationOption(deleteSource: true),
          copiedSourceRecordIds: [700],
        ),
      );
      final repo = FakeMigrationRepository();
      final runner = makeRunner(repo: repo, journal: journal, entries: []);
      await runner.recover();
      expect(repo.copyCalls, isEmpty, reason: 'copy already proven — no redo');
      expect(repo.removeCalls, [1]);
      expect(journal.entries(), isEmpty);
    });

    test('copying → resume re-runs copy (idempotent) then removes', () async {
      await journal.put(
        const MigrationJournalEntry(
          fromMangaId: 1,
          toMangaId: 100,
          state: MigrationPairState.copying,
          options: MigrationOption(deleteSource: true),
        ),
      );
      final repo = FakeMigrationRepository();
      final runner = makeRunner(repo: repo, journal: journal, entries: []);
      await runner.recover();
      expect(repo.copyCalls, [1], reason: 'copy not proven — redo it');
      expect(repo.removeCalls, [1]);
      expect(journal.entries(), isEmpty);
    });

  });
}
