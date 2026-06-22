// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';

/// Web stub: offline storage (and thus local page files) is disabled on web,
/// so this is never reached; it exists only to keep `ServerImage` compiling.
ImageProvider offlineImageProvider(String path) =>
    throw UnsupportedError('Local page images are unavailable on web');
