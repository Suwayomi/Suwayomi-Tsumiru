// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';

void main() {
  group('pageImageExt', () {
    test('prefers the content-type', () {
      expect(pageImageExt('image/jpeg', const []), 'jpg');
      expect(pageImageExt('image/png', const []), 'png');
      expect(pageImageExt('image/webp', const []), 'webp');
      expect(pageImageExt('image/gif', const []), 'gif');
    });
  });
}
