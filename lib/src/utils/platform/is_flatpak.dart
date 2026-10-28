// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Conditional import keeps dart:io out of web builds.
export 'is_flatpak_stub.dart' if (dart.library.io) 'is_flatpak_io.dart';
