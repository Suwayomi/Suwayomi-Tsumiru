// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Auth query parameters must never appear in copyable logs.
final _sensitiveParam = RegExp(
  '([?&](?:token|access_?token|refresh_?token)=)[^&;\\s"\']+',
  caseSensitive: false,
);

/// Redact URL auth-token values while preserving parameter names.
String redactTokens(String input) => input.replaceAllMapped(
    _sensitiveParam, (m) => '${m.group(1)}<redacted>');
