// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';

void main() {
  test('ReaderScrollAmount fractions match the manual-scroll step spec', () {
    expect(ReaderScrollAmount.tiny.fraction, 0.10);
    expect(ReaderScrollAmount.small.fraction, 0.25);
    expect(ReaderScrollAmount.medium.fraction, 0.75);
    expect(ReaderScrollAmount.large.fraction, 0.95);
  });
}
