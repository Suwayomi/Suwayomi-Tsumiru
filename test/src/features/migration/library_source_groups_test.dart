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
    test('counts entries per source and flags obsolete sources', () {
      final groups = groupLibraryBySource([
        m('a', 'Alpha'),
        m('a', 'Alpha'),
        m('d', 'Dead', obsolete: true),
      ]);
      expect(groups.firstWhere((g) => g.sourceId == 'a').count, 2);
      expect(groups.firstWhere((g) => g.sourceId == 'd').isObsolete, isTrue);
    });
  });
}
