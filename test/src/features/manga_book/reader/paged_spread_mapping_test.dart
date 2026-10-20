// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_spread_mapping.dart';

/// Predicate factory: pages in [wide] are wide, the rest portrait.
bool Function(int) wideSet(Set<int> wide) => wide.contains;

/// The RAW page reported at each display position — the read-tracking /
/// seekbar "N / M" contract. This is the sequence the whole feature hinges on.
List<int> primaries(SpreadMapping m) => [
  for (final e in m.entries) e.primaryRaw,
];

void main() {
  const noWide = <int>{};

  group('single mode (identity — the OFF-path contract)', () {
    test('every display position maps to its own raw page', () {
      final m = buildSpreadMapping(
        pageCount: 5,
        doublePages: false,
        splitWide: false,
        splitInvert: false,
        isWide: wideSet(noWide),
      );
      expect(m.length, 5);
      expect(primaries(m), [0, 1, 2, 3, 4]);
      for (var raw = 0; raw < 5; raw++) {
        expect(m.rawToDisplay(raw), raw);
        expect(m.displayToRaw(raw), raw);
        // Full round trip is the identity.
        expect(m.displayToRaw(m.rawToDisplay(raw)), raw);
      }
    });
  });

  group('double mode — pairs', () {
    test('pairs evenly, solos an odd last page, and isolates wide pages', () {
      final even = buildSpreadMapping(
        pageCount: 4,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        isWide: wideSet(noWide),
      );
      expect(even.length, 2);
      expect(even.entries[0], const SpreadEntry(PageUnit(0), PageUnit(1)));
      expect(even.entries[1], const SpreadEntry(PageUnit(2), PageUnit(3)));
      expect(primaries(even), [0, 2]);

      final odd = buildSpreadMapping(
        pageCount: 5,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        isWide: wideSet(noWide),
      );
      expect(odd.length, 3);
      expect(odd.entries[2], const SpreadEntry(PageUnit(4)));
      expect(primaries(odd), [0, 2, 4]);

      // pages: 0 1 [2 wide] 3 4  → (0,1) (2) (3,4)
      final wide = buildSpreadMapping(
        pageCount: 5,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        isWide: wideSet({2}),
      );
      expect(wide.length, 3);
      expect(wide.entries[0], const SpreadEntry(PageUnit(0), PageUnit(1)));
      expect(wide.entries[1], const SpreadEntry(PageUnit(2)));
      expect(wide.entries[2], const SpreadEntry(PageUnit(3), PageUnit(4)));
      expect(primaries(wide), [0, 2, 3]);
    });
  });

  group('split mode — wide page → two halves', () {
    test('a wide page becomes two display entries, both reporting its raw', () {
      // pages: 0 [1 wide] 2  → 0 | 1L | 1R | 2
      final m = buildSpreadMapping(
        pageCount: 3,
        doublePages: false,
        splitWide: true,
        splitInvert: false,
        isWide: wideSet({1}),
      );
      expect(m.length, 4);
      expect(m.entries[0], const SpreadEntry(PageUnit(0)));
      expect(m.entries[1], const SpreadEntry(PageUnit(1, half: PageHalf.left)));
      expect(
        m.entries[2],
        const SpreadEntry(PageUnit(1, half: PageHalf.right)),
      );
      expect(m.entries[3], const SpreadEntry(PageUnit(2)));
      expect(primaries(m), [0, 1, 1, 2]);
    });
  });
}
