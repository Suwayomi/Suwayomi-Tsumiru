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
