// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';

void main() {
  group('effective preferred scanlators', () {
    test('modern empty list overrides legacy preference', () {
      expect(
        MangaMeta.fromJson({
          'flutter_preferredScanlators': '[]',
          'flutter_scanlator': 'Legacy',
        }).effectivePreferredScanlators,
        isEmpty,
      );
    });
    test('modern preferences override legacy preference', () {
      expect(
        MangaMeta.fromJson({
          'flutter_preferredScanlators': '["A","B"]',
          'flutter_scanlator': 'Legacy',
        }).effectivePreferredScanlators,
        ['A', 'B'],
      );
    });
    test('missing modern preference falls back to legacy', () {
      expect(
        MangaMeta.fromJson({
          'flutter_scanlator': 'Legacy',
        }).effectivePreferredScanlators,
        ['Legacy'],
      );
    });
    test('legacy sentinel and absent metadata mean no filtering', () {
      expect(
        MangaMeta.fromJson({
          'flutter_scanlator': MangaMetaKeys.scanlator.key,
        }).effectivePreferredScanlators,
        isEmpty,
      );
      expect(
        MangaMeta.fromJson(const {}).effectivePreferredScanlators,
        isEmpty,
      );
    });
  });

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
