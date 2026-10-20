// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';

void main() {
  const w = 400.0;
  const h = 800.0;

  test('pagedFit maps each scale type to the right BoxFit', () {
    expect(ImageScaleType.fitScreen.pagedFit(w, h).$1, BoxFit.contain);
    expect(ImageScaleType.stretch.pagedFit(w, h).$1, BoxFit.fill);
    expect(ImageScaleType.fitWidth.pagedFit(w, h).$1, BoxFit.fitWidth);
    expect(ImageScaleType.fitHeight.pagedFit(w, h).$1, BoxFit.fitHeight);
    // BoxFit.none would crop the page; the reader's zoom supplies the real 1:1.
    expect(ImageScaleType.originalSize.pagedFit(w, h).$1, BoxFit.contain);
    expect(ImageScaleType.smartFit.pagedFit(w, h).$1, BoxFit.fitWidth);
  });
}
