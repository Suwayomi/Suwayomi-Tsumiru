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
    test('even count pairs cleanly (0,1)(2,3)', () {
      final m = buildSpreadMapping(
        pageCount: 4,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        isWide: wideSet(noWide),
      );
      expect(m.length, 2);
      expect(m.entries[0], const SpreadEntry(PageUnit(0), PageUnit(1)));
      expect(m.entries[1], const SpreadEntry(PageUnit(2), PageUnit(3)));
      expect(primaries(m), [0, 2]);
    });

    test('odd last page solos', () {
      final m = buildSpreadMapping(
        pageCount: 5,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        isWide: wideSet(noWide),
      );
      expect(m.length, 3);
      expect(m.entries[2], const SpreadEntry(PageUnit(4)));
      expect(primaries(m), [0, 2, 4]);
    });
  });

  group('double mode — wide page isolation (Komikku fullPage)', () {
    test('a wide page in the middle solos and realigns pairing', () {
      // pages: 0 1 [2 wide] 3 4  → (0,1) (2) (3,4)
      final m = buildSpreadMapping(
        pageCount: 5,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        isWide: wideSet({2}),
      );
      expect(m.length, 3);
      expect(m.entries[0], const SpreadEntry(PageUnit(0), PageUnit(1)));
      expect(m.entries[1], const SpreadEntry(PageUnit(2)));
      expect(m.entries[2], const SpreadEntry(PageUnit(3), PageUnit(4)));
      expect(primaries(m), [0, 2, 3]);
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

  group('full round-trip sweep across all modes', () {
    // centerMargin does not affect the mapping (it is render-only gap), so the
    // index contract is identical for every centerMargin variant — covered by
    // sweeping the mapping-relevant axes here.
    test('universal invariants hold for every mapping-relevant config', () {
      final configs = <Map<String, dynamic>>[
        {'double': false, 'split': false, 'wide': <int>{}},
        {'double': true, 'split': false, 'wide': <int>{}},
        {
          'double': false,
          'split': true,
          'wide': {1, 4},
        },
        {
          'double': true,
          'split': false,
          'wide': {2},
        },
        {
          'double': true,
          'split': true,
          'wide': {3},
        },
        {
          'double': true,
          'split': false,
          'wide': {0, 5},
        },
      ];
      for (final c in configs) {
        final wide = (c['wide'] as Set<int>);
        for (final invert in [false, true]) {
          final m = buildSpreadMapping(
            pageCount: 6,
            doublePages: c['double'] as bool,
            splitWide: c['split'] as bool,
            splitInvert: invert,
            isWide: wideSet(wide),
          );
          // (1) Every display primary is a real raw page.
          // (2) Primaries are non-decreasing — reading order preserved.
          var prev = -1;
          for (var d = 0; d < m.length; d++) {
            final raw = m.displayToRaw(d);
            expect(raw, inInclusiveRange(0, 5), reason: '$c d=$d');
            expect(
              raw,
              greaterThanOrEqualTo(prev),
              reason: 'primaries monotonic for $c invert=$invert',
            );
            prev = raw;
          }
          // (3) rawToDisplay lands on a spread that actually CONTAINS the raw.
          for (var raw = 0; raw < 6; raw++) {
            final d = m.rawToDisplay(raw);
            expect(d, inInclusiveRange(0, m.length - 1), reason: '$c raw=$raw');
            final e = m.entries[d];
            expect(
              e.first.raw == raw || e.second?.raw == raw,
              isTrue,
              reason: 'rawToDisplay($raw) must contain it for $c',
            );
          }
        }
      }
    });
  });
}
