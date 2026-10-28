// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:queue/queue.dart';

import 'avif_header.dart';
import 'avif_native_io.dart';

bool get avifNormalizationSupported => Platform.isLinux;

Future<Uint8List> normalizeAvifBytes(Uint8List bytes) async {
  if (!avifNormalizationSupported || !isAvifHeader(bytes)) return bytes;
  return await _decodeOffThread(bytes) ?? bytes;
}

/// Called only from a worker isolate.
Uint8List normalizeAvifBytesSync(Uint8List bytes) {
  if (!avifNormalizationSupported || !isAvifHeader(bytes)) return bytes;
  return AvifNative.instance?.decode(bytes) ?? bytes;
}

Future<Uint8List?> _decodeOffThread(Uint8List bytes) async {
  if (AvifNative.instance == null) return null;
  try {
    return await _decodeQueue.add(() => compute(_decodeAvif, bytes));
  } catch (_) {
    return null;
  }
}

Uint8List? _decodeAvif(Uint8List bytes) => AvifNative.instance?.decode(bytes);

/// Bound native decode memory during page prefetch.
final _decodeQueue = Queue(parallel: 2);
