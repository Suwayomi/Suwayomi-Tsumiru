// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/migration_models.dart';

/// Persist each transition before its server mutation to allow crash recovery.
enum MigrationPairState {
  prepared,

  /// Recovery repeats the idempotent copy.
  copying,

  /// Copy completed; recovery may remove the source.
  copied,

  /// Recovery verifies source state before repeating removal.
  removing,

  removed,

  /// Terminal and retryable; the source is retained.
  failed,
}

/// Keyed by source manga ID, which may migrate only once per batch.
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

  /// Recovery must use the original copy flags.
  final MigrationOption options;

  /// Source tracker records to unbind locally after copying.
  final List<int> copiedSourceRecordIds;
  final String? failureReason;

  bool get deleteSource => options.deleteSource;

  MigrationJournalEntry copyWith({
    MigrationPairState? state,
    List<int>? copiedSourceRecordIds,
    String? failureReason,
  }) => MigrationJournalEntry(
    fromMangaId: fromMangaId,
    toMangaId: toMangaId,
    state: state ?? this.state,
    options: options,
    copiedSourceRecordIds: copiedSourceRecordIds ?? this.copiedSourceRecordIds,
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

/// Stores one batch as a single JSON value; each transition rewrites it atomically.
class MigrationJournal {
  MigrationJournal(this._prefs, {this.accountId}) {
    if (accountId != null && accountId!.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId');
    }
  }

  final String? accountId;
  String get _prefsKey => accountId == null
      ? prefsKey
      : '$prefsKey:${Uri.encodeComponent(accountId!)}';

  final SharedPreferences _prefs;
  static const String prefsKey = 'bulk_migration_journal_v1';

  Map<int, MigrationJournalEntry>? _cache;

  Map<int, MigrationJournalEntry> get _entries {
    final cache = _cache;
    if (cache != null) return cache;
    final raw = _prefs.getString(_prefsKey);
    final loaded = <int, MigrationJournalEntry>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        for (final m in list) {
          final e = MigrationJournalEntry.fromJson(m);
          loaded[e.fromMangaId] = e;
        }
      } catch (_) {
      }
    }
    return _cache = loaded;
  }

  List<MigrationJournalEntry> entries() => _entries.values.toList();

  MigrationJournalEntry? entryFor(int fromMangaId) => _entries[fromMangaId];

  Future<void> _flush() async {
    final list = _entries.values.map((e) => e.toJson()).toList();
    await _prefs.setString(_prefsKey, jsonEncode(list));
  }

  /// Caller must await this before the corresponding server mutation.
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
    await _prefs.remove(_prefsKey);
  }
}
