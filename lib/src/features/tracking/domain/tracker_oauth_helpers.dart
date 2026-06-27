// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

/// Returns the full URL to open in the external browser to start OAuth for
/// [trackerId] / [trackerName], given the tracker's [authUrl] base.
///
/// Builds the `state` JSON param exactly as Suwayomi-WebUI does:
///   `{ redirectUrl, trackerId, trackerName }`
/// then appends it URL-encoded to [authUrl].
///
/// [redirectUrl] is the platform callback URL (e.g. `tsumiru://tracker-oauth`
/// on native, or the web-app origin + route on web).
String buildTrackerAuthUrl({
  required String authUrl,
  required int trackerId,
  required String trackerName,
  required String redirectUrl,
}) {
  final state = {
    'redirectUrl': redirectUrl,
    'trackerId': trackerId,
    'trackerName': trackerName,
  };
  final encoded = Uri.encodeComponent(jsonEncode(state));
  return '$authUrl&state=$encoded';
}

/// Parses the `trackerId` from the `state` query parameter of an incoming
/// tracker-OAuth callback URI.
///
/// Returns `null` if the URI has no `state` param, or if `state` is not
/// valid JSON, or if `trackerId` is absent or not an int.
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
