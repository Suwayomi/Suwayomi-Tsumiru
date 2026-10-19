// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Native desktop OS (not web, not mobile). `!kIsWeb` must be first — dart:io
/// `Platform` throws on web.
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

/// Runtimes where a physical keyboard is expected: native desktop or web.
bool get isKeyboardRuntime => kIsWeb || isDesktopPlatform;

/// Test-only override for the Android gates in reader settings. Null
/// (the default) uses the real platform; widget tests set it to true to
/// exercise the Android-only rows on a desktop VM.
@visibleForTesting
bool? debugAndroidOverride;

/// True on Android. Tests opt into the Android-only rows via
/// [debugAndroidOverride]; production reads the real platform.
bool get isAndroidRuntime =>
    debugAndroidOverride ?? (!kIsWeb && Platform.isAndroid);
