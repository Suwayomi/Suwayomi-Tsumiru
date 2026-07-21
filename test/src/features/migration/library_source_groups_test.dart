// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/migration/domain/library_source_groups.dart';

MangaSourceInfo m(String sourceId, String name, {bool obsolete = false}) =>
    (sourceId: sourceId, displayName: name, isObsolete: obsolete);

void main() {
  group('groupLibraryBySource', () {
    test('counts entries per source', () {
      final groups = groupLibraryBySource([
        m('a', 'Alpha'),
        m('a', 'Alpha'),
        m('b', 'Beta'),
      ]);
      expect(groups.firstWhere((g) => g.sourceId == 'a').count, 2);
      expect(groups.firstWhere((g) => g.sourceId == 'b').count, 1);
    });

    test('sorts alphabetically and flags obsolete sources', () {
      final groups = groupLibraryBySource([
        m('z', 'Zeta'),
        m('a', 'Alpha'),
        m('d', 'Dead', obsolete: true),
      ]);
      expect(groups.map((g) => g.sourceId).toList(), ['a', 'd', 'z']);
      expect(groups.firstWhere((g) => g.sourceId == 'd').isObsolete, isTrue);
    });

    test('a source is obsolete if ANY of its entries reports it so', () {
      final groups = groupLibraryBySource([
        m('a', 'Alpha', obsolete: false),
        m('a', 'Alpha', obsolete: true),
      ]);
      expect(groups.single.isObsolete, isTrue);
    });

    test('empty library yields no groups', () {
      expect(groupLibraryBySource([]), isEmpty);
    });
  });
}
