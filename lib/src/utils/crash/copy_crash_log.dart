// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'crash_log.dart';
import 'redact_tokens.dart';

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

/// Redacts copyable logs, prepends header verbatim, and returns null when no readable log exists.
String? crashLogForClipboard(String? path, {String? header}) {
  final raw = readCrashLog(path);
  return raw == null ? null : '${header ?? ''}${redactTokens(raw)}';
}
