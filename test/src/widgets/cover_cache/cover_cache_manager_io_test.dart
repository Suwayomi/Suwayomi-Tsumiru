// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache_manager_io.dart';

class _SupportDirectory extends PathProviderPlatform {
  _SupportDirectory(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

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
    test('accepts the avif major brand', () {
      expect(isAvifHeader(_ftyp('avif', ['mif1', 'miaf'])), isTrue);
    });

    test('accepts the avis major brand', () {
      expect(isAvifHeader(_ftyp('avis', ['avif', 'msf1'])), isTrue);
    });

    test('accepts avif listed as a compatible brand', () {
      expect(isAvifHeader(_ftyp('mif1', ['miaf', 'avif'])), isTrue);
    });

    test('rejects HEIC', () {
      expect(isAvifHeader(_ftyp('heic', ['mif1', 'heic'])), isFalse);
    });

    test('rejects MP4', () {
      expect(isAvifHeader(_ftyp('isom', ['isom', 'mp41'])), isFalse);
    });

    test('rejects a header too short to hold a brand', () {
      expect(isAvifHeader(_ftyp('avif', const []).take(11).toList()), isFalse);
    });

    test('rejects JPEG', () {
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

  group('transcodeAvifInFlight', () {
    test('returned future completes and clears the in-flight entry', () async {
      var calls = 0;
      Future<void> transcode() async {
        calls++;
      }

      await transcodeAvifInFlight(
        'cover-in-flight',
        transcode,
      ).timeout(const Duration(seconds: 5));
      await transcodeAvifInFlight(
        'cover-in-flight',
        transcode,
      ).timeout(const Duration(seconds: 5));

      expect(calls, 2);
    });
  });

  group('createCoverCacheManager', () {
    late Directory support;
    late PathProviderPlatform previousPaths;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('cover-cache-test');
      previousPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _SupportDirectory(support.path);
    });

    tearDown(() async {
      PathProviderPlatform.instance = previousPaths;
      await support.delete(recursive: true);
    });

    test('keeps covers for 90 days, capped at 5000 files', () async {
      final manager = createCoverCacheManager();
      addTearDown(manager.dispose);
      await manager.config.fileSystem.createFile('probe');
      expect(manager.config.cacheKey, 'tsumiruCovers');
      expect(manager.config.stalePeriod, const Duration(days: 90));
      expect(manager.config.maxNrOfCacheObjects, 5000);
    });
  });
}
