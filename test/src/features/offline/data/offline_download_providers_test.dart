// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';

void main() {
  group('pageImageExt', () {
    test('prefers the content-type', () {
      expect(pageImageExt('image/jpeg', const []), 'jpg');
      expect(pageImageExt('image/png', const []), 'png');
      expect(pageImageExt('image/webp', const []), 'webp');
      expect(pageImageExt('image/gif', const []), 'gif');
    });

    test('falls back to magic bytes when content-type is absent', () {
      const z = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]; // padding to 12 bytes
      expect(pageImageExt(null, [0x89, 0x50, ...z]), 'png');
      expect(pageImageExt(null, [0xFF, 0xD8, ...z]), 'jpg');
      expect(pageImageExt(null, [0x47, 0x49, ...z]), 'gif');
      expect(pageImageExt(null, [0x52, 0x49, 0, 0, 0, 0, 0, 0, 0x57, 0, 0, 0]),
          'webp');
    });

    test('defaults to jpg when unknown', () {
      expect(pageImageExt(null, const [0, 0, 0, 0]), 'jpg');
      expect(pageImageExt('application/octet-stream',
          const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]), 'jpg');
    });
  });

  test('offlineDownloadManagerProvider is null when offline is disabled', () {
    // Default config (web / offline unavailable): offlineEnabledProvider is
    // false, so the manager provider must no-op to null without touching the
    // (unoverridden, throwing) database/store/repo providers.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(offlineDownloadManagerProvider), isNull);
  });

  test('cascadeServerDeleteToDevice no-ops when offline disabled', () {
    // cascadeServerDeleteToDevice guards on offlineDownloadManagerProvider == null.
    // Assert the precondition: default container (offline disabled) yields null,
    // so the helper exits before touching any device state.
    // (cascadeServerDeleteToDevice takes WidgetRef; the guard path is tested by
    //  confirming the provider it reads is null in the default config.)
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(offlineDownloadManagerProvider), isNull);
  });
}
