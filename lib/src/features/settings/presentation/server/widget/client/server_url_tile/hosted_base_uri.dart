// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Reads the document's effective base URI on web. The conditional import
// follows the codebase's web-only pattern (default stub, real
// implementation where `dart:js_interop` exists): `!kIsWeb` must be checked
// first at call sites, mirroring `platform_runtime.dart`.
export 'hosted_base_uri_stub.dart'
    if (dart.library.js_interop) 'hosted_base_uri_web.dart';
