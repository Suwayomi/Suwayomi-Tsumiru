// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Use dart:io on native and false on web; defaultTargetPlatform reports Android in tests and browsers.
export 'is_android_native_stub.dart'
    if (dart.library.io) 'is_android_native_io.dart';
