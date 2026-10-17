// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';

void main() {
  for (final stored in ['grid', 'list', 1, '1']) {
    test('ignores retired chapter view preference $stored', () {
      final meta = MangaMeta.fromJson({'flutter_chapterListMode': stored});
      expect(meta, MangaMeta());
      expect(meta.toJson(), isNot(contains('flutter_chapterListMode')));
    });
  }
}
