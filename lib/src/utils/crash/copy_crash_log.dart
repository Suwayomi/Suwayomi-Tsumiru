// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'crash_log.dart';
import 'redact_tokens.dart';

/// Reads the crash log and redacts it — covers entries an older, pre-redaction
/// version wrote. Use this instead of [readCrashLog] for anything user-copyable.
String? crashLogForClipboard(String? path) {
  final raw = readCrashLog(path);
  return raw == null ? null : redactTokens(raw);
}
