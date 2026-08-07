// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';

void main() {
  group('MangaMeta.preferredScanlators parse', () {
    test('decodes a JSON string array', () {
      expect(
        MangaMeta.fromJson({'flutter_preferredScanlators': '["A","B"]'})
            .preferredScanlators,
        ['A', 'B'],
      );
    });
    test('null on empty / non-JSON / non-list', () {
      expect(MangaMeta.fromJson(const {}).preferredScanlators, isNull);
      expect(
          MangaMeta.fromJson({'flutter_preferredScanlators': ''})
              .preferredScanlators,
          isNull);
      expect(
          MangaMeta.fromJson({'flutter_preferredScanlators': 'nope'})
              .preferredScanlators,
          isNull);
      expect(
          MangaMeta.fromJson({'flutter_preferredScanlators': '{}'})
              .preferredScanlators,
          isNull);
    });
    test('enum key matches', () {
      expect(MangaMetaKeys.preferredScanlators.key,
          'flutter_preferredScanlators');
    });
  });
}
