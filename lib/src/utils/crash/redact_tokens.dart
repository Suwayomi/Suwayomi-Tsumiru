// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Matches token/accessToken/access_token/refreshToken/refresh_token query params
// (case-insensitive) — values that must never end up in a copyable log.
final _sensitiveParam = RegExp(
  '([?&](?:token|access_?token|refresh_?token)=)[^&;\\s"\']+',
  caseSensitive: false,
);

/// Replaces the value of any auth token carried in a URL query string with
/// `<redacted>`, preserving the key so the log still reads sensibly.
String redactTokens(String input) => input.replaceAllMapped(
    _sensitiveParam, (m) => '${m.group(1)}<redacted>');
