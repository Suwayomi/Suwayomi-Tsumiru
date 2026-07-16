// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';

// sqlite3 3.x loads its own SQLite via Dart build hooks, so the old
// DynamicLibrary override (pointing the VM test host at libsqlite3.so.0)
// is gone along with the API that provided it.

/// A fresh in-memory [OfflineDatabase] for tests.
OfflineDatabase testOfflineDatabase() {
  return OfflineDatabase(NativeDatabase.memory());
}

/// An on-disk [OfflineDatabase] at [path] — for migration tests that need
/// close-and-reopen semantics.
OfflineDatabase testOfflineDatabaseFile(String path) {
  return OfflineDatabase(NativeDatabase(File(path)));
}
