// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/tracking/domain/tracker_oauth_helpers.dart';

void main() {
  const authUrl =
      'https://myanimelist.net/v1/oauth2/authorize?response_type=code&client_id=abc';
  const trackerId = 1;
  const trackerName = 'MyAnimeList';
  const redirectUrl = 'tsumiru://tracker-oauth';

  group('buildTrackerAuthUrl', () {
    test('starts with the authUrl', () {
      final result = buildTrackerAuthUrl(
        authUrl: authUrl,
        trackerId: trackerId,
        trackerName: trackerName,
        redirectUrl: redirectUrl,
      );
      expect(result, startsWith(authUrl));
    });

    test('contains &state= followed by URL-encoded JSON', () {
      final result = buildTrackerAuthUrl(
        authUrl: authUrl,
        trackerId: trackerId,
        trackerName: trackerName,
        redirectUrl: redirectUrl,
      );
      expect(result, contains('&state='));
    });

    test('decoded state has correct fields', () {
      final result = buildTrackerAuthUrl(
        authUrl: authUrl,
        trackerId: trackerId,
        trackerName: trackerName,
        redirectUrl: redirectUrl,
      );
      final stateEncoded = Uri.parse(result).queryParameters['state']!;
      final stateDecoded =
          jsonDecode(Uri.decodeComponent(stateEncoded)) as Map<String, dynamic>;
      expect(stateDecoded['redirectUrl'], equals(redirectUrl));
      expect(stateDecoded['trackerId'], equals(trackerId));
      expect(stateDecoded['trackerName'], equals(trackerName));
    });
  });

  group('parseTrackerIdFromCallback', () {
    Uri makeUri(Map<String, dynamic> stateMap) {
      final encoded = Uri.encodeComponent(jsonEncode(stateMap));
      return Uri.parse('tsumiru://tracker-oauth?code=xyz&state=$encoded');
    }

    test('returns correct int trackerId from valid callback', () {
      final uri = makeUri(
          {'redirectUrl': redirectUrl, 'trackerId': 1, 'trackerName': 'MAL'});
      expect(parseTrackerIdFromCallback(uri), equals(1));
    });

    test('returns null when state param is absent', () {
      final uri = Uri.parse('tsumiru://tracker-oauth?code=xyz');
      expect(parseTrackerIdFromCallback(uri), isNull);
    });

    test('returns null for malformed JSON in state', () {
      final uri = Uri.parse(
          'tsumiru://tracker-oauth?state=${Uri.encodeComponent('not-json')}');
      expect(parseTrackerIdFromCallback(uri), isNull);
    });

    test('returns null when trackerId is missing from state', () {
      final uri = makeUri({'redirectUrl': redirectUrl});
      expect(parseTrackerIdFromCallback(uri), isNull);
    });

    test('accepts trackerId as a string (int.tryParse)', () {
      final uri = makeUri({'trackerId': '42', 'trackerName': 'MAL'});
      expect(parseTrackerIdFromCallback(uri), equals(42));
    });
  });
}
