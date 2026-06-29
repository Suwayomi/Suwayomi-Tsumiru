// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Resolve (and create) the crash-log file path under the app support dir, so
/// the error handlers can append to it synchronously. Returns null if it can't
/// be set up (logging is best-effort and never blocks startup).
Future<String?> initCrashLog() async {
  try {
    final dir = await getApplicationSupportDirectory();
    final logDir = Directory('${dir.path}/logs');
    logDir.createSync(recursive: true);
    return '${logDir.path}/crash.log';
  } catch (_) {
    return null;
  }
}

/// Append [content] to the crash log. No-op if the path is null or the write
/// fails — crash reporting must never throw.
void writeCrashLog(String? path, String content) {
  if (path == null) return;
  try {
    File(path).writeAsStringSync(content, mode: FileMode.append, flush: true);
  } catch (_) {}
}
