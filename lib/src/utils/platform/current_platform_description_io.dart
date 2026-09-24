// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

/// Native implementation: e.g. `android 15`, `linux 7.2.3`, `macos 15.0`.
String currentPlatformDescription() =>
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
