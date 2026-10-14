// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Read the document base URI on web.
export 'hosted_base_uri_stub.dart'
    if (dart.library.js_interop) 'hosted_base_uri_web.dart';
