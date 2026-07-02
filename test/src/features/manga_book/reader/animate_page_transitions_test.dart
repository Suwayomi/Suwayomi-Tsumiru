// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Komikku "animate page transitions": the paged next/prev animation branch.
// ON → animate over kDuration; OFF → jump instantly (kInstantDuration).

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/app_constants.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/single_page_reader_mode.dart';

void main() {
  group('pagedNavDuration', () {
    test('animate ON → kDuration', () {
      expect(pagedNavDuration(animate: true), kDuration);
    });

    test('animate OFF → instant jump', () {
      expect(pagedNavDuration(animate: false), kInstantDuration);
    });

    test('ON is a real (non-instant) animation', () {
      expect(pagedNavDuration(animate: true) > kInstantDuration, isTrue);
    });
  });
}
