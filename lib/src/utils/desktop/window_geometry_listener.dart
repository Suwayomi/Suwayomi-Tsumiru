// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'window_geometry.dart';
import 'window_geometry_store.dart';

/// Saves window size/maximized state to prefs when the user changes it.
/// Debounced because `onWindowResize` fires continuously on Linux (there is no
/// end-of-resize `onWindowResized` there).
class WindowGeometryListener with WindowListener {
  WindowGeometryListener(this._prefs);
  final SharedPreferences _prefs;
  Timer? _debounce;
  bool _persisting = false;

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _persist);
  }

  Future<void> _persist() async {
    // Serialize: interleaved isMaximized/getSize reads corrupt the saved bounds.
    if (_persisting) {
      _scheduleSave();
      return;
    }
    _persisting = true;
    try {
      await _persistNow();
    } finally {
      _persisting = false;
    }
  }

  Future<void> _persistNow() async {
    final maximized = await windowManager.isMaximized();
    if (shouldPersistSize(isMaximized: maximized)) {
      final size = await windowManager.getSize();
      await saveWindowGeometry(
          _prefs, WindowGeometry(size: size, maximized: false));
    } else {
      // Keep the last saved size; only flip the maximized flag.
      final existing = loadWindowGeometry(_prefs);
      await saveWindowGeometry(
          _prefs, WindowGeometry(size: existing.size, maximized: true));
    }
  }

  @override
  void onWindowResize() => _scheduleSave();
  @override
  void onWindowResized() => _scheduleSave(); // macOS/Windows end-of-resize
  @override
  void onWindowMaximize() => _scheduleSave();
  @override
  void onWindowUnmaximize() => _scheduleSave();

  @override
  void onWindowClose() {
    // Best-effort flush of a pending debounced save; quitting right after a
    // resize would otherwise restore stale geometry next launch.
    _debounce?.cancel();
    _persist();
  }
}

void attachWindowGeometryListener(SharedPreferences prefs) {
  windowManager.addListener(WindowGeometryListener(prefs));
}
