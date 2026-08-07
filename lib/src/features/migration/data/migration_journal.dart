// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/migration_models.dart';

/// Write-ahead lifecycle of one source→target migration pair. Each transition
/// is persisted BEFORE the matching server mutation, so a crash leaves a marker
/// to reconcile on relaunch.
enum MigrationPairState {
  /// Queued, matched to a target, nothing sent yet.
  prepared,

  /// About to copy data onto the target (recovery: re-run copy — idempotent).
  copying,

  /// Copy verified complete; source not yet removed (recovery: verify + remove).
  copied,

  /// About to remove the source (recovery: verify source state, then remove).
  removing,

  /// Source removed — terminal success.
  removed,

  /// A step failed; source deliberately kept — terminal, retryable.
  failed,
}

/// One journalled pair. Keyed on [fromMangaId] (a source migrates once per
/// batch); [toMangaId] identifies the target for idempotency across a crash.
class MigrationJournalEntry {
  const MigrationJournalEntry({
    required this.fromMangaId,
    required this.toMangaId,
    required this.state,
    required this.options,
    this.copiedSourceRecordIds = const [],
    this.failureReason,
  });

  final int fromMangaId;
  final int toMangaId;
  final MigrationPairState state;

  /// The exact options the batch ran with, persisted so recovery re-copies with
  /// the same flags instead of silently reverting to defaults.
  final MigrationOption options;

  /// Source track-record ids copied to the target, to unbind on removal.
  final List<int> copiedSourceRecordIds;
  final String? failureReason;

  bool get deleteSource => options.deleteSource;

  MigrationJournalEntry copyWith({
    MigrationPairState? state,
    List<int>? copiedSourceRecordIds,
    String? failureReason,
  }) =>
      MigrationJournalEntry(
        fromMangaId: fromMangaId,
        toMangaId: toMangaId,
        state: state ?? this.state,
        options: options,
        copiedSourceRecordIds:
            copiedSourceRecordIds ?? this.copiedSourceRecordIds,
        failureReason: failureReason ?? this.failureReason,
      );

  Map<String, dynamic> toJson() => {
        'from': fromMangaId,
        'to': toMangaId,
        'state': state.name,
        'opts': options.toJson(),
        'recs': copiedSourceRecordIds,
        if (failureReason != null) 'err': failureReason,
      };

  factory MigrationJournalEntry.fromJson(Map<String, dynamic> j) =>
      MigrationJournalEntry(
        fromMangaId: j['from'] as int,
        toMangaId: j['to'] as int,
        state: MigrationPairState.values.byName(j['state'] as String),
        options: j['opts'] != null
            ? MigrationOption.fromJson(j['opts'] as Map<String, dynamic>)
            : const MigrationOption(),
        copiedSourceRecordIds:
            (j['recs'] as List?)?.map((e) => e as int).toList() ?? const [],
        failureReason: j['err'] as String?,
      );
}

/// Durable per-pair journal for one bulk migration batch, persisted as a single
/// JSON blob in [SharedPreferences]. Small enough that a full rewrite per
/// transition is cheap and atomic enough for crash-safety. Only ONE batch is
/// journalled at a time.
class MigrationJournal {
  MigrationJournal(this._prefs);

  final SharedPreferences _prefs;
  static const String prefsKey = 'bulk_migration_journal_v1';

  Map<int, MigrationJournalEntry>? _cache;

  Map<int, MigrationJournalEntry> get _entries {
    final cache = _cache;
    if (cache != null) return cache;
    final raw = _prefs.getString(prefsKey);
    final loaded = <int, MigrationJournalEntry>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        for (final m in list) {
          final e = MigrationJournalEntry.fromJson(m);
          loaded[e.fromMangaId] = e;
        }
      } catch (_) {
        // Corrupt journal — drop it rather than wedging the runner.
      }
    }
    return _cache = loaded;
  }

  /// Current journal contents (recovery reads these on relaunch).
  List<MigrationJournalEntry> entries() => _entries.values.toList();

  MigrationJournalEntry? entryFor(int fromMangaId) => _entries[fromMangaId];

  Future<void> _flush() async {
    final list = _entries.values.map((e) => e.toJson()).toList();
    await _prefs.setString(prefsKey, jsonEncode(list));
  }

  /// Write-ahead a transition: caller MUST await this before the corresponding
  /// server mutation so a crash leaves the pre-mutation marker.
  Future<void> put(MigrationJournalEntry entry) async {
    _entries[entry.fromMangaId] = entry;
    await _flush();
  }

  Future<void> advance(
    int fromMangaId,
    MigrationPairState state, {
    List<int>? copiedSourceRecordIds,
    String? failureReason,
  }) async {
    final existing = _entries[fromMangaId];
    if (existing == null) return;
    _entries[fromMangaId] = existing.copyWith(
      state: state,
      copiedSourceRecordIds: copiedSourceRecordIds,
      failureReason: failureReason,
    );
    await _flush();
  }

  Future<void> removeEntry(int fromMangaId) async {
    _entries.remove(fromMangaId);
    await _flush();
  }

  Future<void> clear() async {
    _cache = {};
    await _prefs.remove(prefsKey);
  }
}
