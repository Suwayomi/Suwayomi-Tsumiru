// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import 'account_storage_recovery.dart';

Future<void> reconcileAccountCatalogues(
  String source,
  String target, {
  Map<int, bool> choices = const {},
}) => Isolate.run(() => _reconcile(source, target, choices));

String _quoted(String name) => '"${name.replaceAll('"', '""')}"';

const _readingFields = ['is_read', 'last_page_read', 'is_bookmarked'];
const _syncFlags = ['progress_dirty', 'read_state_dirty', 'bookmark_dirty'];
const _pendingFields = [..._syncFlags, 'read_state_manual'];

String _reading(Map<String, Object?> row) => jsonEncode({
  for (final field in [..._readingFields, ..._pendingFields, 'last_read_at'])
    if (row.containsKey(field)) field: row[field],
});

bool _matchesResolvedState(String saved, Map<String, Object?> current) {
  final resolved = jsonDecode(saved) as Map<String, dynamic>;
  final state = {...current};
  // A successful sync clears pending flags without invalidating the choice.
  for (final field in _syncFlags) {
    if (resolved[field] == 1 && state[field] == 0) state[field] = 1;
  }
  return _reading(state) == saved;
}

void _backup(Database database, String path, {String? backupPath}) {
  final backup = File(backupPath ?? '$path.recovery-backup');
  final type = FileSystemEntity.typeSync(backup.path, followLinks: false);
  if (type == FileSystemEntityType.file) return;
  if (type != FileSystemEntityType.notFound) {
    throw FileSystemException('Invalid recovery backup', backup.path);
  }
  final pending = File('${backup.path}.pending');
  final pendingType = FileSystemEntity.typeSync(
    pending.path,
    followLinks: false,
  );
  if (pendingType == FileSystemEntityType.file) {
    pending.deleteSync();
  } else if (pendingType != FileSystemEntityType.notFound) {
    throw FileSystemException('Invalid recovery backup', pending.path);
  }
  database.execute('VACUUM INTO ?', [pending.path]);
  pending.renameSync(backup.path);
}

void _check(Database database, String path) {
  final result = database.select('PRAGMA quick_check');
  if (result.length != 1 || result.single.values.single != 'ok') {
    throw FileSystemException('Catalogue failed integrity check', path);
  }
}

void _reconcile(String source, String target, Map<int, bool> choices) {
  final original = sqlite3.open(source, mode: OpenMode.readOnly);
  try {
    final current = sqlite3.open(target, mode: OpenMode.readWrite);
    try {
      _check(original, source);
      _check(current, target);
      _backup(original, source, backupPath: '$target.legacy-recovery-backup');
      _backup(current, target);
      final tables = original.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_account_%'",
      );
      if (tables.any((r) => r['name'] == 'offline_chapters')) {
        current.execute(
          'CREATE TABLE IF NOT EXISTS _account_recovery_choices (chapter_id INTEGER PRIMARY KEY, original_state TEXT NOT NULL, resolved_state TEXT NOT NULL)',
        );
      }
      final mangaTitles = <int, String>{
        if (tables.any((r) => r['name'] == 'offline_mangas'))
          for (final manga in original.select(
            'SELECT id,title FROM offline_mangas',
          ))
            manga['id'] as int: manga['title'] as String,
      };
      current.execute('BEGIN IMMEDIATE');
      try {
        final conflicts = <AccountProgressConflict>[];
        for (final table in tables) {
          final name = table['name'] as String;
          final targetColumns = current.select(
            'PRAGMA table_info(${_quoted(name)})',
          );
          if (targetColumns.isEmpty) {
            throw StateError(
              'Recovery cannot merge an unknown catalogue table: $name',
            );
          }
          final sourceColumns = original
              .select('PRAGMA table_info(${_quoted(name)})')
              .map((r) => r['name'] as String)
              .toSet();
          final columns = targetColumns
              .map((r) => r['name'] as String)
              .where(sourceColumns.contains)
              .toList();
          final keys = targetColumns
              .where((r) => (r['pk'] as int) > 0)
              .map((r) => r['name'] as String)
              .toList();
          if (keys.isEmpty || !keys.every(sourceColumns.contains)) {
            throw StateError(
              'Recovery cannot identify catalogue records: $name',
            );
          }
          final where = keys.map((key) => '${_quoted(key)} = ?').join(' AND ');
          for (final row in original.select('SELECT * FROM ${_quoted(name)}')) {
            final key = keys.map((key) => row[key]).toList();
            final matches = current.select(
              'SELECT * FROM ${_quoted(name)} WHERE $where',
              key,
            );
            if (matches.isEmpty) {
              current.execute(
                'INSERT INTO ${_quoted(name)} (${columns.map(_quoted).join(',')}) VALUES (${columns.map((_) => '?').join(',')})',
                columns.map((column) => row[column]).toList(),
              );
              if (name == 'offline_chapters') {
                final inserted = current
                    .select('SELECT * FROM ${_quoted(name)} WHERE $where', key)
                    .single;
                current.execute(
                  'INSERT OR REPLACE INTO _account_recovery_choices VALUES (?,?,?)',
                  [row['id'], _reading(row), _reading(inserted)],
                );
              }
              continue;
            }
            if (name != 'offline_chapters') continue;
            final existing = matches.single;
            final id = row['id'] as int;
            final originalState = _reading(row);
            final currentState = _reading(existing);
            if (originalState == currentState) {
              current.execute(
                'INSERT OR REPLACE INTO _account_recovery_choices VALUES (?,?,?)',
                [id, originalState, currentState],
              );
              continue;
            }
            final saved = current.select(
              'SELECT original_state,resolved_state FROM _account_recovery_choices WHERE chapter_id=?',
              [id],
            );
            if (saved.isNotEmpty &&
                saved.single['original_state'] == originalState &&
                _matchesResolvedState(
                  saved.single['resolved_state'] as String,
                  existing,
                )) {
              continue;
            }
            if (!choices.containsKey(id)) {
              conflicts.add(
                AccountProgressConflict(
                  chapterId: id,
                  name: [
                    if (mangaTitles[row['manga_id']] != null)
                      mangaTitles[row['manga_id']]!,
                    row['name'] as String,
                  ].join(' · '),
                  originalPage: row['last_page_read'] as int,
                  currentPage: existing['last_page_read'] as int,
                  originalRead: row['is_read'] == 1,
                  currentRead: existing['is_read'] == 1,
                  originalBookmarked: row['is_bookmarked'] == 1,
                  currentBookmarked: existing['is_bookmarked'] == 1,
                  originalLastReadAt: row['last_read_at'] as String?,
                  currentLastReadAt: existing['last_read_at'] as String?,
                  originalPendingFields: [
                    for (final field in _syncFlags)
                      if (row[field] == 1) field,
                  ],
                  currentPendingFields: [
                    for (final field in _syncFlags)
                      if (existing[field] == 1) field,
                  ],
                  originalReadStateManual: row['read_state_manual'] == 1,
                  currentReadStateManual: existing['read_state_manual'] == 1,
                ),
              );
              continue;
            }
            if (choices[id] == true) {
              final updates = <String, Object?>{
                // Recovery copies an edit; it must not manufacture a new read.
                for (final field in [
                  ..._readingFields,
                  ..._pendingFields,
                  'last_read_at',
                ])
                  if (columns.contains(field)) field: row[field],
              };
              current.execute(
                'UPDATE ${_quoted(name)} SET ${updates.keys.map((k) => '${_quoted(k)}=?').join(',')} WHERE $where',
                [...updates.values, ...key],
              );
            }
            final resolved = current
                .select('SELECT * FROM ${_quoted(name)} WHERE $where', key)
                .single;
            current.execute(
              'INSERT OR REPLACE INTO _account_recovery_choices VALUES (?,?,?)',
              [id, originalState, _reading(resolved)],
            );
          }
        }
        if (conflicts.isNotEmpty) {
          throw AccountStorageProgressConflict(conflicts);
        }
        _check(current, target);
        current.execute('COMMIT');
      } catch (_) {
        current.execute('ROLLBACK');
        rethrow;
      }
    } finally {
      current.close();
    }
  } finally {
    original.close();
  }
}
