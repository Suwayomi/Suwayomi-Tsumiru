// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// True only when running natively on Android. Unlike `defaultTargetPlatform`
// (which reports `android` inside `flutter test` and on Android browsers), this
// reads `dart:io`'s `Platform.isAndroid` on native and is hard-coded `false` on
// web — so it's correct on real Android, in unit tests (host is Linux/macOS),
// and web, all at once. Used to gate the Android-only foreground-service
// download path against the desktop/web main-isolate pump.
export 'is_android_native_stub.dart'
    if (dart.library.io) 'is_android_native_io.dart';
