// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

class BackgroundDownloadLock {
  BackgroundDownloadLock(this.lockFile);

  final File lockFile;
  Database? _database;

  File get _yieldFile => File('${lockFile.path}.yield');

  Future<bool> acquire(String holder) async {
    if (_database != null) return false;
    await lockFile.parent.create(recursive: true);
    final database = sqlite3.open('${lockFile.path}.sqlite');
    try {
      database.execute('PRAGMA busy_timeout=0');
      database.execute('BEGIN IMMEDIATE');
    } on SqliteException catch (error) {
      database.close();
      if (error.resultCode == 5 || error.resultCode == 6) return false;
      rethrow;
    } catch (_) {
      database.close();
      rethrow;
    }
    _database = database;
    try {
      await _yieldFile.delete();
    } catch (_) {}
    return true;
  }

  Future<void> requestYield() async {
    try {
      await _yieldFile.parent.create(recursive: true);
      await _yieldFile.writeAsString('', flush: true);
    } catch (_) {}
  }

  Future<bool> yieldRequested() => _yieldFile.exists();

  Future<void> release() async {
    final database = _database;
    _database = null;
    if (database == null) return;
    try {
      database.execute('ROLLBACK');
    } finally {
      database.close();
    }
  }
}
