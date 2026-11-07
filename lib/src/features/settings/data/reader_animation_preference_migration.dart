// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:shared_preferences/shared_preferences.dart';

// Scroll animation merged into Animate page transitions; either off keeps it off.
Future<void> migrateReaderAnimationPreference(SharedPreferences prefs) async {
  const migratedKey = 'readerAnimationMerged';
  if (prefs.getBool(migratedKey) != true) {
    if (prefs.getBool('scrollAnimation') == false ||
        prefs.getBool('animatePageTransitions') == false) {
      await prefs.setBool('animatePageTransitions', false);
    }
    await prefs.remove('scrollAnimation');
    await prefs.setBool(migratedKey, true);
  }
}
