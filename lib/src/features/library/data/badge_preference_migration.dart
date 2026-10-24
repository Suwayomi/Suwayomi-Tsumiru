// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/enum.dart';

/// Marks completed migration so later user choices survive relaunch.
const kBadgePrefsMigratedKey = 'badgePrefsRevampMigrated';

const _kLegacyUnreadBadge = 'unreadBadge';
const _kLegacyLocalBadge = 'localBadge';
const _kLegacyUseLangIcon = 'useLangIcon';

/// Migrates legacy badge preferences once, preserving disabled unread badges and source icons.
Future<void> migrateBadgePreferences(SharedPreferences prefs) async {
  if (prefs.getBool(kBadgePrefsMigratedKey) == true) return;

  if (prefs.getBool(_kLegacyUnreadBadge) == false &&
      prefs.getInt(DBKeys.unreadBadgeMode.name) == null) {
    await prefs.setInt(
      DBKeys.unreadBadgeMode.name,
      UnreadBadgeMode.hidden.index,
    );
  }

  // The legacy language-icon switch only applied while the language badge was enabled.
  final langIconStandsIn = prefs.getBool(_kLegacyUseLangIcon) == true &&
      prefs.getBool(DBKeys.languageBadge.name) == true;

  if (langIconStandsIn || prefs.getBool(_kLegacyLocalBadge) == true) {
    await prefs.setBool(DBKeys.sourceBadge.name, true);
  }
  if (langIconStandsIn) {
    await prefs.setBool(DBKeys.languageBadge.name, false);
  }

  await prefs.setBool(kBadgePrefsMigratedKey, true);
}
