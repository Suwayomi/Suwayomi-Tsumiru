// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Web-safe entry point for the crash-log file writer. The real implementation
// needs `dart:io` (native only); on web this swaps in a no-op stub so main.dart
// — which compiles for web too — still builds.
export 'crash_log_stub.dart' if (dart.library.io) 'crash_log_io.dart';
