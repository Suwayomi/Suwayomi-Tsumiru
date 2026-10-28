// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';

void main() {
  for (final stored in ChapterListMode.values) {
    test('parses chapter view preference $stored', () {
      final meta = MangaMeta.fromJson({'flutter_chapterListMode': stored.name});
      expect(meta.chapterListMode, stored);
      expect(meta.toJson()['flutter_chapterListMode'], stored.name);
    });
  }
}
