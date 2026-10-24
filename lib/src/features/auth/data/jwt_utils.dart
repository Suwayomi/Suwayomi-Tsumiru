// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

/// Reads exp without verifying the signature; malformed claims return null.
/// RFC 7519 allows fractional epoch seconds, which are floored.
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

// JWT omits the padding required by base64Url.decode.
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
