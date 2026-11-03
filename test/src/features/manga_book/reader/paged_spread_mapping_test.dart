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

  group('offset double spreads — WebUI getDoublePageModePages parity', () {
    test('offset off pairs from page 0 (the current contract)', () {
      // | 0+1 | 2+3 | 4+5 | 6+7 | 8 |
      final m = buildSpreadMapping(
        pageCount: 9,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        isWide: wideSet(noWide),
      );
      expect(m.entries, const [
        SpreadEntry(PageUnit(0), PageUnit(1)),
        SpreadEntry(PageUnit(2), PageUnit(3)),
        SpreadEntry(PageUnit(4), PageUnit(5)),
        SpreadEntry(PageUnit(6), PageUnit(7)),
        SpreadEntry(PageUnit(8)),
      ]);
    });

    test('offset on solos the first page and shifts every pair by one', () {
      // | 0 | 1+2 | 3+4 | 5+6 | 7+8 |
      final m = buildSpreadMapping(
        pageCount: 9,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        offsetDoublePages: true,
        isWide: wideSet(noWide),
      );
      expect(m.entries, const [
        SpreadEntry(PageUnit(0)),
        SpreadEntry(PageUnit(1), PageUnit(2)),
        SpreadEntry(PageUnit(3), PageUnit(4)),
        SpreadEntry(PageUnit(5), PageUnit(6)),
        SpreadEntry(PageUnit(7), PageUnit(8)),
      ]);
      // Seekbar contract: reading-first raw per slot, last slot completes the chapter.
      expect(primaries(m), [0, 1, 3, 5, 7]);
      expect([for (final e in m.entries) e.progressRaw], [0, 2, 4, 6, 8]);
      expect(m.rawToDisplay(4), 2);
      expect(m.rawToDisplay(8), 4);
    });

    test('offset on with an even-slot wide page: phase breaks around it', () {
      // pages: 0 1 [2 wide] 3 4 → the wide occupies two book slots, so the
      // offset phase cannot resume cleanly and neighbours stay solo.
      final m = buildSpreadMapping(
        pageCount: 5,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        offsetDoublePages: true,
        isWide: wideSet({2}),
      );
      expect(m.entries, const [
        SpreadEntry(PageUnit(0)),
        SpreadEntry(PageUnit(1)),
        SpreadEntry(PageUnit(2)),
        SpreadEntry(PageUnit(3)),
        SpreadEntry(PageUnit(4)),
      ]);
    });

    test('offset on with an odd-slot wide page: pairs resume after it', () {
      // pages: 0 1 2 [3 wide] 4 5 → | 0 | 1+2 | [3] | 4+5 |
      final m = buildSpreadMapping(
        pageCount: 6,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        offsetDoublePages: true,
        isWide: wideSet({3}),
      );
      expect(m.entries, const [
        SpreadEntry(PageUnit(0)),
        SpreadEntry(PageUnit(1), PageUnit(2)),
        SpreadEntry(PageUnit(3)),
        SpreadEntry(PageUnit(4), PageUnit(5)),
      ]);
    });

    test('offset off with an odd-slot wide page: parity holds after it', () {
      // pages: 0 1 2 [3 wide] 4 5 → the wide occupies two slots, so page 4
      // lands on an odd slot (no backward partner) and stays solo.
      final m = buildSpreadMapping(
        pageCount: 6,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        isWide: wideSet({3}),
      );
      expect(m.entries, const [
        SpreadEntry(PageUnit(0), PageUnit(1)),
        SpreadEntry(PageUnit(2)),
        SpreadEntry(PageUnit(3)),
        SpreadEntry(PageUnit(4)),
        SpreadEntry(PageUnit(5)),
      ]);
    });

    test('offset on with split wide pages: halves pair like normal units', () {
      // pages: [0 wide] 1 2 → 0L | 0R+1 | 2
      final m = buildSpreadMapping(
        pageCount: 3,
        doublePages: true,
        splitWide: true,
        splitInvert: false,
        offsetDoublePages: true,
        isWide: wideSet({0}),
      );
      expect(m.entries, const [
        SpreadEntry(PageUnit(0, half: PageHalf.left)),
        SpreadEntry(PageUnit(0, half: PageHalf.right), PageUnit(1)),
        SpreadEntry(PageUnit(2)),
      ]);
    });
  });
}
