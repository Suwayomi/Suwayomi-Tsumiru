// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Test override; null uses the real platform.
@visibleForTesting
bool? debugDesktopPlatformOverride;

/// Check !kIsWeb first: dart:io Platform throws on web.
bool get isDesktopPlatform =>
    debugDesktopPlatformOverride ??
    (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS));

bool get isKeyboardRuntime => kIsWeb || isDesktopPlatform;

/// Test override for Android-only controls; null uses the real platform.
@visibleForTesting
bool? debugAndroidOverride;

/// Test override for macOS layout; null uses the real platform.
@visibleForTesting
bool? debugMacOSOverride;

bool get isMacOSRuntime =>
    debugMacOSOverride ?? (!kIsWeb && Platform.isMacOS);

bool get isAndroidRuntime =>
    debugAndroidOverride ?? (!kIsWeb && Platform.isAndroid);
