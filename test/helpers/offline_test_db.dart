// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:sqlite3/open.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';


bool _configured = false;

/// Point the `sqlite3` package at the versioned host library in tests.
///
/// On a device `sqlite3_flutter_libs` bundles the lib, but the Dart VM test
/// host has only `libsqlite3.so.0` (no unversioned `libsqlite3.so`, which ships
/// in the `-dev` package). Test-only workaround; no production effect.
void _ensureSqlite() {
  if (_configured) return;
  _configured = true;
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
}

/// A fresh in-memory [OfflineDatabase] for tests.
OfflineDatabase testOfflineDatabase() {
  _ensureSqlite();
  return OfflineDatabase(NativeDatabase.memory());
}

/// An on-disk [OfflineDatabase] at [path] — for migration tests that need
/// close-and-reopen semantics. The sqlite3 host shim is applied so the same
/// versioned library is used as in [testOfflineDatabase].
OfflineDatabase testOfflineDatabaseFile(String path) {
  _ensureSqlite();
  return OfflineDatabase(NativeDatabase(File(path)));
}
