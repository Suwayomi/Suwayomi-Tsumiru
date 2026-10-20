// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/tracking/domain/tracker_oauth_helpers.dart';

void main() {
  const redirectUrl = 'tsumiru://tracker-oauth';

  group('parseTrackerIdFromCallback', () {
    Uri makeUri(Map<String, dynamic> stateMap) {
      final encoded = Uri.encodeComponent(jsonEncode(stateMap));
      return Uri.parse('tsumiru://tracker-oauth?code=xyz&state=$encoded');
    }

    test('reads the tracker id, including a string form, or null', () {
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

      // A missing, malformed or id-less state has no tracker.
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
