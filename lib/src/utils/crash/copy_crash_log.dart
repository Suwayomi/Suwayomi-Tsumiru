// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'crash_log.dart';
import 'redact_tokens.dart';

/// Builds the self-describing preamble for a copied log, so a log pasted into
/// a bug report says which build produced it.
String crashLogHeader({
  required String appVersion,
  required String buildNumber,
  required String serverVersion,
  required String platform,
}) =>
    'Tsumiru v$appVersion (build $buildNumber)\n'
    'Server: $serverVersion\n'
    'Platform: $platform\n'
    '---\n';

/// Reads the crash log and redacts it — covers entries an older, pre-redaction
/// version wrote. Use this instead of [readCrashLog] for anything user-copyable.
///
/// A [header] (see [crashLogHeader]) is prepended verbatim: it carries only
/// version strings and an OS name, so it is never run through [redactTokens].
/// Still returns null when there is no readable log, header or not.
String? crashLogForClipboard(String? path, {String? header}) {
  final raw = readCrashLog(path);
  return raw == null ? null : '${header ?? ''}${redactTokens(raw)}';
}
