// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Web-safe entry point for the background-download controller.
//
// The real controller (`background_download_controller.dart`) pulls in
// `dart:io` + `flutter_foreground_task` and only compiles on native platforms;
// on web this exports a no-op stub instead. Web-compiled code
// (`offline_download_providers.dart`, `main.dart`) must import THIS shim, never
// the controller directly.
export 'background_download_controller_stub.dart'
    if (dart.library.io) 'background_download_controller.dart';
