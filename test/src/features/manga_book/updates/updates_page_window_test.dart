// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';

void main() {
  group('splitPageWindow', () {
    test('one row past the page means another page follows', () {
      final page = splitPageWindow(List.generate(51, (i) => i), 50);
      expect(page.nodes, List.generate(50, (i) => i));
      expect(page.hasNextPage, isTrue);
    });

    test('a full page and nothing past it is the last page', () {
      final page = splitPageWindow(List.generate(50, (i) => i), 50);
      expect(page.nodes, hasLength(50));
      expect(page.hasNextPage, isFalse);
    });
  });
}
