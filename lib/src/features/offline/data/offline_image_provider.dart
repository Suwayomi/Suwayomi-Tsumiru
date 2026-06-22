// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Resolves a local on-device page file to an [ImageProvider]. Native only
// (dart:io `FileImage`); the web stub throws — offline is disabled on web, so
// it is never called there, but this keeps `ServerImage` web-compilable.
export 'offline_image_provider_stub.dart'
    if (dart.library.io) 'offline_image_provider_io.dart';
