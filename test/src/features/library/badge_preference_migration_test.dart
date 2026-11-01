// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/library/data/badge_preference_migration.dart';
import 'package:tsumiru/src/features/settings/data/grid_cover_preference_migration.dart';

Future<SharedPreferences> _migrated(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  await migrateBadgePreferences(prefs);
  return prefs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saved cover size carries over once to the minimum width', () async {
    SharedPreferences.setMockInitialValues({'gridMangaCoverWidth': 192.0});
    final prefs = await SharedPreferences.getInstance();
    await migrateGridCoverPreference(prefs);
    expect(prefs.getDouble('gridMangaCoverMinWidth'), 128.0);
    expect(prefs.containsKey('gridMangaCoverWidth'), isFalse);

    await prefs.setDouble('gridMangaCoverMinWidth', 150.0);
    await migrateGridCoverPreference(prefs);
    expect(prefs.getDouble('gridMangaCoverMinWidth'), 150.0);
  });

  group('unreadBadge → unreadBadgeMode', () {
    test('off stays off, as Hidden', () async {
      final prefs = await _migrated({'unreadBadge': false});
      expect(prefs.getInt('unreadBadgeMode'), UnreadBadgeMode.hidden.index);
    });

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
