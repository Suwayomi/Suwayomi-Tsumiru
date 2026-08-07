// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'offline_database.dart';
import 'offline_page_store.dart';
import 'offline_page_store_io.dart';
import 'offline_paths.dart';

/// Native (mobile + desktop) implementation: open the drift catalog on a file
/// under the app-support directory, plus the dart:io page store.
Future<({OfflineDatabase db, OfflinePaths paths, OfflinePageStore store})?>
    openOfflineStorage() async {
  final support = await getApplicationSupportDirectory();
  final baseDir = p.join(support.path, 'offline');
  await Directory(baseDir).create(recursive: true);
  final paths = OfflinePaths(baseDir);
  final db = OfflineDatabase(
    NativeDatabase.createInBackground(File(p.join(baseDir, 'catalog.sqlite'))),
  );
  return (db: db, paths: paths, store: IoOfflinePageStore(paths));
}
