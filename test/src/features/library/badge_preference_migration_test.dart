// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/library/data/badge_preference_migration.dart';

Future<SharedPreferences> _migrated(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  await migrateBadgePreferences(prefs);
  return prefs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('unreadBadge → unreadBadgeMode', () {
    test('off stays off, as Hidden', () async {
      final prefs = await _migrated({'unreadBadge': false});
      expect(prefs.getInt('unreadBadgeMode'), UnreadBadgeMode.hidden.index);
    });

    test(
      'on leaves the new key alone, so it keeps its Count default',
      () async {
        final prefs = await _migrated({'unreadBadge': true});
        expect(prefs.getInt('unreadBadgeMode'), isNull);
      },
    );

    test('never set leaves the new key alone', () async {
      final prefs = await _migrated({});
      expect(prefs.getInt('unreadBadgeMode'), isNull);
    });

    test('a mode the user already chose is not overwritten', () async {
      final prefs = await _migrated({
        'unreadBadge': false,
        'unreadBadgeMode': UnreadBadgeMode.dot.index,
      });
      expect(prefs.getInt('unreadBadgeMode'), UnreadBadgeMode.dot.index);
    });
  });

  group('localBadge → sourceBadge', () {
    test('Local Source badge on keeps a badge, via the source badge', () async {
      final prefs = await _migrated({'localBadge': true, 'sourceBadge': false});
      expect(prefs.getBool('sourceBadge'), isTrue);
    });

    test('Local Source badge off changes nothing', () async {
      final prefs = await _migrated({
        'localBadge': false,
        'sourceBadge': false,
      });
      expect(prefs.getBool('sourceBadge'), isFalse);
    });
  });

  group('useLangIcon → sourceBadge', () {
    test('the source icon moves out of the language slot', () async {
      final prefs = await _migrated({
        'languageBadge': true,
        'useLangIcon': true,
        'sourceBadge': false,
      });
      expect(prefs.getBool('sourceBadge'), isTrue);
      // The slot now always draws a flag, which is not what they picked.
      expect(prefs.getBool('languageBadge'), isFalse);
    });

    test('the source icon is not left drawn twice', () async {
      // This combination drew the same icon in both slots before the revamp.
      // Collapsing it to one is the intent, not a dropped badge.
      final prefs = await _migrated({
        'languageBadge': true,
        'useLangIcon': true,
        'sourceBadge': true,
      });
      expect(prefs.getBool('sourceBadge'), isTrue);
      expect(prefs.getBool('languageBadge'), isFalse);
    });

    test('a plain language badge keeps drawing a language badge', () async {
      final prefs = await _migrated({
        'languageBadge': true,
        'useLangIcon': false,
      });
      expect(prefs.getBool('languageBadge'), isTrue);
      expect(prefs.getBool('sourceBadge'), isNull);
    });

    test('inert when the language badge itself was off', () async {
      final prefs = await _migrated({
        'languageBadge': false,
        'useLangIcon': true,
      });
      expect(prefs.getBool('languageBadge'), isFalse);
      expect(prefs.getBool('sourceBadge'), isNull);
    });
  });

  test('a fresh install is left entirely alone', () async {
    final prefs = await _migrated({});
    expect(prefs.getInt('unreadBadgeMode'), isNull);
    expect(prefs.getBool('sourceBadge'), isNull);
    expect(prefs.getBool('languageBadge'), isNull);
  });

  test('a later deliberate change survives the next launch', () async {
    final prefs = await _migrated({'unreadBadge': false, 'localBadge': true});
    expect(prefs.getInt('unreadBadgeMode'), UnreadBadgeMode.hidden.index);

    // The user turns both back the other way, then relaunches.
    await prefs.setInt('unreadBadgeMode', UnreadBadgeMode.count.index);
    await prefs.setBool('sourceBadge', false);
    await migrateBadgePreferences(prefs);

    expect(prefs.getInt('unreadBadgeMode'), UnreadBadgeMode.count.index);
    expect(prefs.getBool('sourceBadge'), isFalse);
  });
}
