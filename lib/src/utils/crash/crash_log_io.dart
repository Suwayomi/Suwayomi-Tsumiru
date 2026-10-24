// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

// Trim past maxBytes to keepBytes on a line boundary; normal writes only append.
const int _maxBytes = 256 * 1024;
const int _keepBytes = 128 * 1024;

/// Prepare a path for synchronous error handlers; null on failure, never blocks startup.
Future<String?> initCrashLog() async {
  try {
    final dir = await getApplicationSupportDirectory();
    final logDir = Directory('${dir.path}/logs');
    logDir.createSync(recursive: true);
    final path = '${logDir.path}/crash.log';
    _trimIfOversized(File(path));
    return path;
  } catch (_) {
    return null;
  }
}

/// No-op on missing path or write failure; crash reporting must never throw.
void writeCrashLog(String? path, String content) {
  if (path == null) return;
  try {
    final file = File(path);
    file.writeAsStringSync(content, mode: FileMode.append, flush: true);
    _trimIfOversized(file);
  } catch (_) {}
}

/// Trim at maxBytes to the last keepBytes on a line boundary; never throws.
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

/// Read the crash log; null when missing or empty.
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

/// Delete the log; no-op for a missing path/file and never throws.
void clearCrashLog(String? path) {
  if (path == null) return;
  try {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  } catch (_) {}
}
