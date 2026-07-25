// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

// Hive lowercased the box name ("graphqlClientStore") for its file names.
const _legacyFiles = ['graphqlclientstore.hive', 'graphqlclientstore.lock'];

/// Returns the deleted box's size in bytes (null when there was none), so the
/// caller can log how big the file had grown — the number that diagnoses the
/// startup-OOM class from a single crash-log line.
Future<int?> deleteLegacyGraphqlCacheBox() async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    int? boxBytes;
    for (final name in _legacyFiles) {
      final f = File('${docs.path}/$name');
      if (!f.existsSync()) continue;
      if (name.endsWith('.hive')) boxBytes = f.lengthSync();
      f.deleteSync();
    }
    return boxBytes;
  } catch (_) {
    // Best-effort: a failed cleanup must never block startup.
    return null;
  }
}
