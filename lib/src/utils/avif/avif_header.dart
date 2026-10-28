// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

const avifHeaderProbeBytes = 256;

bool isAvifHeader(List<int> bytes) {
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(4, 8)) != 'ftyp') {
    return false;
  }
  final boxSize =
      (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  if (boxSize < 16) {
    return false;
  }
  final end = boxSize < bytes.length ? boxSize : bytes.length;
  bool isAvifBrand(int offset) {
    final brand = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    return brand == 'avif' || brand == 'avis';
  }

  if (isAvifBrand(8)) {
    return true;
  }
  for (var offset = 16; offset + 4 <= end; offset += 4) {
    if (isAvifBrand(offset)) {
      return true;
    }
  }
  return false;
}
