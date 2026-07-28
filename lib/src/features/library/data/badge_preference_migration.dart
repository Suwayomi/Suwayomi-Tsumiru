// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/enum.dart';

/// Set once the seeding below has run, so a later deliberate change by the user
/// survives the next launch.
const kBadgePrefsMigratedKey = 'badgePrefsRevampMigrated';

const _kLegacyUnreadBadge = 'unreadBadge';
const _kLegacyLocalBadge = 'localBadge';
const _kLegacyUseLangIcon = 'useLangIcon';

/// Carries pre-revamp badge settings onto the keys that replaced them, so an
/// upgrade doesn't read as the app forgetting them.
///
/// * `unreadBadge` off becomes [UnreadBadgeMode.hidden]. Everyone else is
///   already covered by the new key's own default.
/// * `localBadge` folded into `sourceBadge`, which now draws the Local Source
///   folder glyph itself. Turning it on is the only way to keep that badge; it
///   also brings source icons the user didn't ask for, which beats silently
///   dropping a badge they did.
/// * `useLangIcon` put a source icon in the language slot. The language slot
///   now always draws a flag, so the source icon moves to `sourceBadge` and the
///   language badge turns off — the same single icon on the cover as before.
Future<void> migrateBadgePreferences(SharedPreferences prefs) async {
  if (prefs.getBool(kBadgePrefsMigratedKey) == true) return;

  if (prefs.getBool(_kLegacyUnreadBadge) == false &&
      prefs.getInt(DBKeys.unreadBadgeMode.name) == null) {
    await prefs.setInt(
      DBKeys.unreadBadgeMode.name,
      UnreadBadgeMode.hidden.index,
    );
  }

  // Only meaningful while the language badge was actually on: the old settings
  // page nested this switch under it, and the renderer gated on it too.
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
