// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import 'window_geometry.dart';

const _kWidth = 'window.width';
const _kHeight = 'window.height';
const _kMaximized = 'window.maximized';

WindowGeometry loadWindowGeometry(SharedPreferences prefs) {
  // Wrong-typed preferences throw; use defaults so corruption cannot abort startup.
  try {
    final w = prefs.getDouble(_kWidth);
    final h = prefs.getDouble(_kHeight);
    return WindowGeometry(
      size: (w != null && h != null) ? Size(w, h) : null,
      maximized: prefs.getBool(_kMaximized) ?? false,
    );
  } on TypeError {
    return const WindowGeometry();
  }
}

Future<void> saveWindowGeometry(
    SharedPreferences prefs, WindowGeometry g) async {
  if (g.size != null) {
    await prefs.setDouble(_kWidth, g.size!.width);
    await prefs.setDouble(_kHeight, g.size!.height);
  }
  await prefs.setBool(_kMaximized, g.maximized);
}
