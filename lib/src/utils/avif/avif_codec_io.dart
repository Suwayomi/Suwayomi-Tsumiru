// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import 'avif_header.dart';
import 'avif_native_io.dart';

/// Only the Linux build carries the AVIF shim.
bool get avifNormalizationSupported => Platform.isLinux;

/// Converts AVIF to PNG off the UI isolate; returns [bytes] unchanged otherwise.
Future<Uint8List> normalizeAvifBytes(Uint8List bytes) async {
  if (!avifNormalizationSupported || !isAvifHeader(bytes)) return bytes;
  return await _decodeOffThread(bytes) ?? bytes;
}

/// Sync variant for callers already running inside a background isolate.
Uint8List normalizeAvifBytesSync(Uint8List bytes) {
  if (!avifNormalizationSupported || !isAvifHeader(bytes)) return bytes;
  return AvifNative.instance?.decode(bytes) ?? bytes;
}

Future<Uint8List?> _decodeOffThread(Uint8List bytes) async {
  if (AvifNative.instance == null) return null;
  await _decodeGate.acquire();
  try {
    return await compute(_decodeAvif, bytes);
  } catch (_) {
    return null;
  } finally {
    _decodeGate.release();
  }
}

Uint8List? _decodeAvif(Uint8List bytes) => AvifNative.instance?.decode(bytes);

final _decodeGate = _DecodeGate(2);

/// Caps concurrent AVIF decodes so a reader prefetch cannot flood the shim.
class _DecodeGate {
  _DecodeGate(this._limit);

  final int _limit;
  int _active = 0;
  final _waiters = Queue<Completer<void>>();

  Future<void> acquire() {
    if (_active < _limit) {
      _active++;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }
    _active--;
  }
}
