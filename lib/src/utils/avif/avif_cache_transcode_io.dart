// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:typed_data';

import 'avif_codec.dart';
import 'avif_header.dart';

const _pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/// Replaces an AVIF cache file with PNG in place; a failed conversion keeps the original.
Future<bool> transcodeAvifFileToPng(File file) async {
  final before = await _statOrNull(file);
  if (before == null) return true;
  if (!await _startsWithAvifHeader(file)) return true;
  final original = await file.readAsBytes();
  final converted = await normalizeAvifBytes(original);
  if (identical(converted, original) || !_isPng(converted)) return false;

  final temp = File(
    '${file.path}.tsumiru-avif-'
    '${DateTime.now().microsecondsSinceEpoch}-${_tempNonce++}.tmp',
  );
  try {
    await temp.writeAsBytes(converted, flush: true);
    final current = await _statOrNull(file);
    if (current == null || !_sameFile(before, current)) {
      await temp.delete();
      return false;
    }
    await temp.rename(file.path);
  } catch (_) {
    try {
      await temp.delete();
    } catch (_) {}
    return false;
  }
  return true;
}

int _tempNonce = 0;

Future<FileStat?> _statOrNull(File file) async {
  try {
    return await file.stat();
  } catch (_) {
    return null;
  }
}

Future<bool> _startsWithAvifHeader(File file) async {
  try {
    if (await file.length() < 12) return false;
    final header = await file
        .openRead(0, avifHeaderProbeBytes)
        .expand((chunk) => chunk)
        .toList();
    return isAvifHeader(header);
  } catch (_) {
    return false;
  }
}

bool _sameFile(FileStat before, FileStat after) =>
    before.size == after.size &&
    before.modified == after.modified &&
    before.changed == after.changed;

bool _isPng(Uint8List bytes) {
  if (bytes.length < _pngSignature.length) return false;
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) return false;
  }
  return true;
}
