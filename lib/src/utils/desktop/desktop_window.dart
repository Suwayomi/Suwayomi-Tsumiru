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

// Linux minimum is mirrored in linux/my_application.cc where window_manager's minimum is lost.
final kMinWindowSize = isDesktopPlatform && Platform.isLinux
    ? const Size(360, 360)
    : const Size(600, 600);
const kDefaultWindowSize = Size(1280, 900);

/// Restore and prepare the hidden desktop window; no-op on web/mobile.
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
    await windowManager.setPreventClose(true);
    attachWindowGeometryListener(prefs);
    // Wait for Flutter's first frame before showing the window to avoid a blank startup.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await windowManager.show();
      await windowManager.focus();
    });
  });
}
