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
    test('starts with the authUrl and carries the state JSON', () {
      final result = buildTrackerAuthUrl(
        authUrl: authUrl,
        trackerId: trackerId,
        trackerName: trackerName,
        redirectUrl: redirectUrl,
      );
      expect(result, startsWith(authUrl));
      expect(result, contains('&state='));
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

    test('reads the tracker id, including a string form', () {
      expect(
        parseTrackerIdFromCallback(
          makeUri({
            'redirectUrl': redirectUrl,
            'trackerId': 1,
            'trackerName': 'MAL',
          }),
        ),
        equals(1),
      );
      expect(
        parseTrackerIdFromCallback(
          makeUri({'trackerId': '42', 'trackerName': 'MAL'}),
        ),
        equals(42),
      );
    });

    test('returns null for a missing, malformed or id-less state', () {
      expect(
        parseTrackerIdFromCallback(
          Uri.parse('tsumiru://tracker-oauth?code=xyz'),
        ),
        isNull,
      );
      expect(
        parseTrackerIdFromCallback(
          Uri.parse(
            'tsumiru://tracker-oauth?state=${Uri.encodeComponent('not-json')}',
          ),
        ),
        isNull,
      );
      expect(
        parseTrackerIdFromCallback(makeUri({'redirectUrl': redirectUrl})),
        isNull,
      );
    });
  });
}
