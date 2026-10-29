// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/avif/avif_file_io.dart';
import 'package:tsumiru/src/utils/avif/avif_header.dart';

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

void main() {
  group('transcodeAvifFileToPng', () {
    late Directory tempDir;
    setUp(() => tempDir = Directory.systemTemp.createTempSync('tsumiru-avif-'));
    tearDown(() => tempDir.deleteSync(recursive: true));

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

    test('encoded AVIF above the size cap is left in place', () async {
      final file = File('${tempDir.path}/huge.avif');
      final handle = file.openSync(mode: FileMode.write);
      handle
        ..setPositionSync(avifMaxEncodedBytes)
        ..writeByteSync(0)
        ..setPositionSync(0)
        ..writeFromSync(_ftypAvif())
        ..closeSync();
      final length = file.lengthSync();
      expect(length, avifMaxEncodedBytes + 1);
      expect(await transcodeAvifFileToPng(file), isFalse);
      expect(file.lengthSync(), length);
      expect(
        tempDir.listSync().whereType<File>().where(
          (entry) => entry.path.endsWith('.tmp'),
        ),
        isEmpty,
      );
    });
  });
}
