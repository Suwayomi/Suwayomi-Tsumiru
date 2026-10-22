// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'pending_tracker_oauth_store.dart';

PendingTrackerOAuthStore createPendingTrackerOAuthStore() =>
    SqlitePendingTrackerOAuthStore();

class SqlitePendingTrackerOAuthStore implements PendingTrackerOAuthStore {
  SqlitePendingTrackerOAuthStore({String? path}) : _explicitPath = path;
  final String? _explicitPath;

  Future<File> _file() async => File(
    _explicitPath ??
        p.join(
          (await getApplicationSupportDirectory()).path,
          'tracker-oauth.sqlite',
        ),
  );

  Future<T> _database<T>({
    required bool create,
    required T absent,
    required T Function(Database db) action,
  }) async {
    final file = await _file();
    if (!create) {
      try {
        final probe = await file.open(mode: FileMode.read);
        await probe.close();
      } on FileSystemException catch (error) {
        if (error.osError?.errorCode == 2) return absent;
        rethrow;
      }
    }
    if (create) await file.parent.create(recursive: true);
    final db = sqlite3.open(
      file.path,
      mode: create ? OpenMode.readWriteCreate : OpenMode.readWrite,
    );
    try {
      db.execute('PRAGMA busy_timeout=0');
      db.execute('PRAGMA synchronous=FULL');
      db.execute(
        'CREATE TABLE IF NOT EXISTS pending (id INTEGER PRIMARY KEY CHECK (id=1), payload TEXT NOT NULL)',
      );
      return action(db);
    } finally {
      db.close();
    }
  }

  Future<bool> _change({
    required bool create,
    required bool absent,
    required bool Function(Database db) action,
  }) async {
    try {
      return await _database(
        create: create,
        absent: absent,
        action: (db) {
          db.execute('BEGIN IMMEDIATE');
          try {
            final changed = action(db);
            db.execute('COMMIT');
            return changed;
          } catch (_) {
            db.execute('ROLLBACK');
            rethrow;
          }
        },
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> read() => _database(
    create: false,
    absent: null,
    action: (db) {
      final rows = db.select('SELECT payload FROM pending WHERE id=1');
      return rows.isEmpty ? null : rows.single['payload'] as String;
    },
  );

  @override
  Future<bool> replace(String payload) => _change(
    create: true,
    absent: false,
    action: (db) {
      db.execute(
        'INSERT INTO pending (id,payload) VALUES (1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
        [payload],
      );
      return true;
    },
  );

  @override
  Future<bool> claim(String expectedPayload) => _change(
    create: false,
    absent: false,
    action: (db) {
      db.execute('DELETE FROM pending WHERE id=1 AND payload=?', [
        expectedPayload,
      ]);
      return db.updatedRows > 0;
    },
  );

  @override
  Future<bool> clearIfNonce(String nonce) => _change(
    create: false,
    absent: false,
    action: (db) {
      final rows = db.select('SELECT payload FROM pending WHERE id=1');
      if (rows.isEmpty) return false;
      final payload = rows.single['payload'] as String;
      final decoded = jsonDecode(payload);
      if (decoded is! Map || decoded['nonce'] != nonce) return false;
      db.execute('DELETE FROM pending WHERE id=1 AND payload=?', [payload]);
      return db.updatedRows > 0;
    },
  );

  @override
  Future<bool> cancel() => _change(
    create: false,
    absent: true,
    action: (db) {
      db.execute('DELETE FROM pending WHERE id=1');
      return true;
    },
  );
}
