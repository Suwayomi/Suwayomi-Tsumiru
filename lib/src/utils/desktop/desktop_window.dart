// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../platform/platform_runtime.dart';
import 'window_geometry.dart';
import 'window_geometry_listener.dart';
import 'window_geometry_store.dart';

// Deliberately small so the window can shrink to the app's compact layout;
// just large enough that it can't collapse to an unusable sliver.
const kMinWindowSize = Size(300, 400);
const kDefaultWindowSize = Size(1280, 720);

/// Initialise the desktop window: hide the OS title bar, restore the saved
/// size/maximized state, and show only once Flutter is ready (no white flash).
/// No-op on web/mobile.
Future<void> initDesktopWindow(SharedPreferences prefs) async {
  if (!isDesktopPlatform) return;

  await windowManager.ensureInitialized();

  final saved = loadWindowGeometry(prefs);
  final restoreSize = resolveRestoreSize(
    saved,
    fallback: kDefaultWindowSize,
    min: kMinWindowSize,
  );

  final options = WindowOptions(
    size: restoreSize,
    minimumSize: kMinWindowSize,
    center: saved.size == null,
    titleBarStyle: TitleBarStyle.hidden,
    // macOS: keep the native traffic lights floating over our surface.
    windowButtonVisibility: Platform.isMacOS,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setMinimumSize(kMinWindowSize);
    if (saved.maximized) {
      await windowManager.maximize();
    } else {
      await windowManager.setSize(restoreSize);
    }
    attachWindowGeometryListener(prefs);
    // Show after Flutter's first frame, not here — the rest of startup (Hive,
    // migrations, auth preload) still runs before runApp, and showing early
    // flashes a blank window on slow starts.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await windowManager.show();
      await windowManager.focus();
    });
  });
}
