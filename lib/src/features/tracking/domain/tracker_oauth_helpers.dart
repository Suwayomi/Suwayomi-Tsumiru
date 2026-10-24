// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

/// Preserves bridge state, adds the optional native nonce, and appends URL-encoded JSON to authUrl.
/// [redirectUrl] is the native callback URL or web-app origin plus callback route.
String buildTrackerAuthUrl({
  required String authUrl,
  required int trackerId,
  required String trackerName,
  required String redirectUrl,
  String? nonce,
}) {
  final state = {
    'redirectUrl': redirectUrl,
    'trackerId': trackerId,
    'trackerName': trackerName,
    'nonce': ?nonce,
  };
  final encoded = Uri.encodeComponent(jsonEncode(state));
  return '$authUrl&state=$encoded';
}

/// Returns null for missing/malformed state or a trackerId that is not an int.
int? parseTrackerIdFromCallback(Uri callbackUri) {
  final rawState = callbackUri.queryParameters['state'];
  if (rawState == null) return null;
  try {
    final decoded = Uri.decodeComponent(rawState);
    final map = jsonDecode(decoded);
    if (map is Map<String, dynamic>) {
      final id = map['trackerId'];
      if (id is int) return id;
      if (id is String) return int.tryParse(id);
    }
    return null;
  } catch (_) {
    return null;
  }
}
