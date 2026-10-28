// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/avif/avif_codec.dart';
import 'package:tsumiru/src/utils/avif/avif_file_io.dart';

List<int> _ftypAvif() => [
  0,
  0,
  0,
  24,
  ...'ftyp'.codeUnits,
  ...'avif'.codeUnits,
  0,
  0,
  0,
  0,
  ...'mif1'.codeUnits,
  ...'miaf'.codeUnits,
];

final _pngBytes = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0,
  0,
  0,
  0,
]);

void main() {
  group('normalizeAvifBytes', () {
    test('returns bytes untouched when they cannot be transcoded', () async {
      expect(await normalizeAvifBytes(_pngBytes), same(_pngBytes));
      expect(normalizeAvifBytesSync(_pngBytes), same(_pngBytes));

      final malformed = Uint8List.fromList([..._ftypAvif(), 0, 1, 2, 3]);
      expect(await normalizeAvifBytes(malformed), same(malformed));
      expect(normalizeAvifBytesSync(malformed), same(malformed));
    });
  });

  group('transcodeAvifFileToPng', () {
    late Directory tempDir;
    setUp(() => tempDir = Directory.systemTemp.createTempSync('tsumiru-avif-'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('leaves non-AVIF cache files byte-identical', () async {
      final file = File('${tempDir.path}/page.png')
        ..writeAsBytesSync(_pngBytes);
      expect(await transcodeAvifFileToPng(file), isTrue);
      expect(file.readAsBytesSync(), _pngBytes);
    });

    test('malformed AVIF never replaces the original', () async {
      final original = Uint8List.fromList([..._ftypAvif(), 0, 1, 2, 3]);
      final file = File('${tempDir.path}/page.avif')
        ..writeAsBytesSync(original);
      expect(await transcodeAvifFileToPng(file), isFalse);
      expect(file.readAsBytesSync(), original);
      expect(
        tempDir.listSync().whereType<File>().where(
          (entry) => entry.path.endsWith('.tmp'),
        ),
        isEmpty,
      );
    });
  });
}
