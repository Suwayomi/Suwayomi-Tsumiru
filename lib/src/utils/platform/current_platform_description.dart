// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Web-safe entry point for the OS name/version string used in the copied
// debug-log header. The real implementation needs `dart:io` (native only); on
// web this swaps in a stub so callers that compile for web still build.
export 'current_platform_description_stub.dart'
    if (dart.library.io) 'current_platform_description_io.dart';
