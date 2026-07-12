// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

// Append-only and rarely opened, so cap it: past _maxBytes, trim to the last
// _keepBytes on a line boundary. Amortized — normal writes just append.
const int _maxBytes = 256 * 1024;
const int _keepBytes = 128 * 1024;

/// Resolve (and create) the crash-log file path under the app support dir, so
/// the error handlers can append to it synchronously. Returns null if it can't
/// be set up (logging is best-effort and never blocks startup).
Future<String?> initCrashLog() async {
  try {
    final dir = await getApplicationSupportDirectory();
    final logDir = Directory('${dir.path}/logs');
    logDir.createSync(recursive: true);
    final path = '${logDir.path}/crash.log';
    // Migration: cap a log that grew unbounded before this shipped, on launch
    // rather than only on the next error write.
    _trimIfOversized(File(path));
    return path;
  } catch (_) {
    return null;
  }
}

/// Append [content] to the crash log, keeping it bounded. No-op if the path is
/// null or the write fails — crash reporting must never throw.
void writeCrashLog(String? path, String content) {
  if (path == null) return;
  try {
    final file = File(path);
    file.writeAsStringSync(content, mode: FileMode.append, flush: true);
    _trimIfOversized(file);
  } catch (_) {}
}

/// Trim the log to its last [_keepBytes] (on a line boundary) once it passes
/// [_maxBytes]. Best-effort; never throws.
void _trimIfOversized(File file) {
  try {
    if (!file.existsSync() || file.lengthSync() <= _maxBytes) return;
    final bytes = file.readAsBytesSync();
    var start = bytes.length - _keepBytes;
    final nl = bytes.indexOf(0x0A, start); // '\n'
    if (nl != -1 && nl + 1 < bytes.length) start = nl + 1;
    file.writeAsBytesSync(bytes.sublist(start), flush: true);
  } catch (_) {}
}

/// Read the whole crash log so the UI can let a user copy it — they can't reach
/// the app's private files directory themselves. Null if missing/empty.
String? readCrashLog(String? path) {
  if (path == null) return null;
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final content = file.readAsStringSync();
    return content.isEmpty ? null : content;
  } catch (_) {
    return null;
  }
}

/// Delete the crash log so it starts fresh. No-op if the path is null or the
/// file is missing; never throws.
void clearCrashLog(String? path) {
  if (path == null) return;
  try {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  } catch (_) {}
}
