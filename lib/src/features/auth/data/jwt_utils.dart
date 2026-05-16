// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

/// Decodes the `exp` claim out of a JWT. Returns `null` for any
/// malformed input (wrong segment count, invalid base64, invalid
/// JSON, missing/non-numeric `exp`).
///
/// Does NOT verify the signature — that is the server's job. We only
/// use this to size the proactive-refresh Timer so the access token
/// rotates before it expires during a reading session.
///
/// Per RFC 7519, `exp` is a NumericDate — a JSON number representing
/// seconds since the Unix epoch. The spec allows non-integer values,
/// so we accept any finite `num` and floor it.
DateTime? decodeJwtExp(String jwt) {
  try {
    final segments = jwt.split('.');
    if (segments.length != 3) return null;
    final payload = _base64UrlDecodeWithPadding(segments[1]);
    if (payload == null) return null;
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) return null;
    final exp = decoded['exp'];
    if (exp is! num) return null;
    if (exp.isNaN || exp.isInfinite) return null;
    final seconds = exp.floor();
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  } catch (_) {
    return null;
  }
}

/// `base64Url.decode` requires padding; the JWT spec strips it.
/// Re-add the missing `=` characters before decoding.
String? _base64UrlDecodeWithPadding(String segment) {
  try {
    final pad = (4 - segment.length % 4) % 4;
    final padded = segment + ('=' * pad);
    final bytes = base64Url.decode(padded);
    return utf8.decode(bytes);
  } catch (_) {
    return null;
  }
}
