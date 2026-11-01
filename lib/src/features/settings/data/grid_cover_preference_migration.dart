// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/db_keys.dart';

const kGridCoverWidthMin = 100.0;
const kGridCoverWidthMax = 999.0;

Future<void> migrateGridCoverPreference(
  SharedPreferences prefs, {
  double windowWidth = 0,
}) async {
  const legacyKey = 'gridMangaCoverWidth';
  final newKey = DBKeys.gridMangaCoverMinWidth.name;
  if (prefs.containsKey(newKey)) return;
  final oldWidth = prefs.getDouble(legacyKey);
  if (oldWidth == null) return;

  const spacing = 2.0;
  final columns = math.max(1, (windowWidth / (oldWidth + spacing)).ceil());
  final migratedWidth = windowWidth > 0
      ? (windowWidth + spacing) / (columns + 0.5) - spacing
      : oldWidth * 2 / 3;
  final minWidth = migratedWidth
      .clamp(kGridCoverWidthMin, kGridCoverWidthMax)
      .toDouble();
  if (await prefs.setDouble(newKey, minWidth)) {
    await prefs.remove(legacyKey);
  }
}
