// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/multichapter_continuous_reader_mode.dart';

void main() {
  group('autoScrollDelta', () {
    test('advances one viewport over the interval', () {
      final d = autoScrollDelta(viewport: 1000, intervalSeconds: 5, dtMs: 5000);
      expect(d, closeTo(1000, 0.001));
    });
  });
}
