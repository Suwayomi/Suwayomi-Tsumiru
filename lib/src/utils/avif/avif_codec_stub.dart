// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

bool get avifNormalizationSupported => false;

Future<Uint8List> normalizeAvifBytes(Uint8List bytes) async => bytes;

Uint8List normalizeAvifBytesSync(Uint8List bytes) => bytes;
