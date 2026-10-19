// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Test-only override for [isDesktopPlatform]. Null (the default) uses the
/// real platform; widget tests set it to exercise the desktop strips and
/// bars on a non-desktop VM (or to force them off on desktop).
@visibleForTesting
bool? debugDesktopPlatformOverride;

/// Native desktop OS (not web, not mobile). `!kIsWeb` must be first — dart:io
/// `Platform` throws on web.
bool get isDesktopPlatform =>
    debugDesktopPlatformOverride ??
    (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS));

/// Runtimes where a physical keyboard is expected: native desktop or web.
bool get isKeyboardRuntime => kIsWeb || isDesktopPlatform;

/// Test-only override for the Android gates in reader settings. Null
/// (the default) uses the real platform; widget tests set it to true to
/// exercise the Android-only rows on a desktop VM.
@visibleForTesting
bool? debugAndroidOverride;

/// Test-only override for the macOS top-bar/sidebar branch (traffic-lights
/// inset instead of the logo block, 80 px collapsed sidebar). Null (the
/// default) uses the real platform; widget tests set it to exercise the macOS
/// layout on a Linux VM.
@visibleForTesting
bool? debugMacOSOverride;

/// True on macOS. Tests opt into the macOS layout via [debugMacOSOverride];
/// production reads the real platform.
bool get isMacOSRuntime =>
    debugMacOSOverride ?? (!kIsWeb && Platform.isMacOS);

/// True on Android. Tests opt into the Android-only rows via
/// [debugAndroidOverride]; production reads the real platform.
bool get isAndroidRuntime =>
    debugAndroidOverride ?? (!kIsWeb && Platform.isAndroid);
