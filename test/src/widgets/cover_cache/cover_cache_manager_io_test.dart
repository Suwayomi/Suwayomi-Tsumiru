// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache_manager_io.dart';

List<int> _ftyp(String major, List<String> compatible) {
  final size = 16 + 4 * compatible.length;
  return [
    0,
    0,
    0,
    size,
    ...'ftyp'.codeUnits,
    ...major.codeUnits,
    0,
    0,
    0,
    0,
    for (final brand in compatible) ...brand.codeUnits,
  ];
}

void main() {
  group('isAvifHeader', () {
    test('accepts AVIF brands and rejects everything else', () {
      // Accept: avif major, avis major, and avif as a compatible brand.
      expect(isAvifHeader(_ftyp('avif', ['mif1', 'miaf'])), isTrue);
      expect(isAvifHeader(_ftyp('avis', ['avif', 'msf1'])), isTrue);
      expect(isAvifHeader(_ftyp('mif1', ['miaf', 'avif'])), isTrue);

      // Reject: HEIC and MP4, a short header, and JPEG.
      expect(isAvifHeader(_ftyp('heic', ['mif1', 'heic'])), isFalse);
      expect(isAvifHeader(_ftyp('isom', ['isom', 'mp41'])), isFalse);
      expect(isAvifHeader(_ftyp('avif', const []).take(11).toList()), isFalse);
      expect(
        isAvifHeader([
          0xff,
          0xd8,
          0xff,
          0xe0,
          0,
          0x10,
          0x4a,
          0x46,
          0x49,
          0x46,
          0,
          1,
        ]),
        isFalse,
      );
    });
  });
}
