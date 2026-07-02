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
List<int> primaries(SpreadMapping m) =>
    [for (final e in m.entries) e.primaryRaw];

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

    test('empty chapter yields an empty mapping', () {
      final m = buildSpreadMapping(
        pageCount: 0,
        doublePages: false,
        splitWide: false,
        splitInvert: false,
        isWide: wideSet(noWide),
      );
      expect(m.isEmpty, isTrue);
      // Out-of-range lookups never throw.
      expect(m.displayToRaw(0), 0);
      expect(m.rawToDisplay(3), 0);
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

    test('raw→display maps BOTH pages of a pair to the same spread', () {
      final m = buildSpreadMapping(
        pageCount: 4,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        isWide: wideSet(noWide),
      );
      expect(m.rawToDisplay(0), 0);
      expect(m.rawToDisplay(1), 0); // second page of pair 0 → spread 0
      expect(m.rawToDisplay(2), 1);
      expect(m.rawToDisplay(3), 1);
    });

    test('displayToRaw always reports the reading-first page of the pair', () {
      final m = buildSpreadMapping(
        pageCount: 4,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        isWide: wideSet(noWide),
      );
      // Jumping to the SECOND page of a pair lands on the pair and reports the
      // FIRST page — the deliberate double-page tracking behavior.
      expect(m.displayToRaw(m.rawToDisplay(1)), 0);
      expect(m.displayToRaw(m.rawToDisplay(3)), 2);
      // First page of each pair round-trips exactly.
      expect(m.displayToRaw(m.rawToDisplay(0)), 0);
      expect(m.displayToRaw(m.rawToDisplay(2)), 2);
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

    test('a wide page never pairs with a following page', () {
      // pages: 0 [1 wide] 2  → (0) (1) (2)
      final m = buildSpreadMapping(
        pageCount: 3,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        isWide: wideSet({1}),
      );
      expect(primaries(m), [0, 1, 2]);
      expect(m.entries.every((e) => !e.isPair), isTrue);
    });

    test('two consecutive wide pages each solo', () {
      final m = buildSpreadMapping(
        pageCount: 4,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        isWide: wideSet({1, 2}),
      );
      // 0 [1w] [2w] 3 → (0) (1) (2) (3)
      expect(primaries(m), [0, 1, 2, 3]);
      // Round-trip every raw page.
      for (var raw = 0; raw < 4; raw++) {
        expect(m.displayToRaw(m.rawToDisplay(raw)), raw);
      }
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
      expect(m.entries[1],
          const SpreadEntry(PageUnit(1, half: PageHalf.left)));
      expect(m.entries[2],
          const SpreadEntry(PageUnit(1, half: PageHalf.right)));
      expect(m.entries[3], const SpreadEntry(PageUnit(2)));
      expect(primaries(m), [0, 1, 1, 2]);
    });

    test('invert swaps which half shows first', () {
      final m = buildSpreadMapping(
        pageCount: 1,
        doublePages: false,
        splitWide: true,
        splitInvert: true,
        isWide: wideSet({0}),
      );
      expect(m.entries[0].first.half, PageHalf.right);
      expect(m.entries[1].first.half, PageHalf.left);
    });

    test('rawToDisplay lands on the FIRST half of a split page', () {
      final m = buildSpreadMapping(
        pageCount: 3,
        doublePages: false,
        splitWide: true,
        splitInvert: false,
        isWide: wideSet({1}),
      );
      expect(m.rawToDisplay(1), 1); // first half's display index
      expect(m.displayToRaw(m.rawToDisplay(1)), 1);
      // Page after the split still round-trips.
      expect(m.rawToDisplay(2), 3);
      expect(m.displayToRaw(3), 2);
    });

    test('portrait pages are untouched when split is on', () {
      final m = buildSpreadMapping(
        pageCount: 3,
        doublePages: false,
        splitWide: true,
        splitInvert: false,
        isWide: wideSet(noWide),
      );
      expect(primaries(m), [0, 1, 2]);
      expect(m.entries.every((e) => e.first.half == PageHalf.full), isTrue);
    });
  });

  group('split + double combined', () {
    test('a lone wide page splits then its halves pair back together', () {
      // page 0 wide → 0L,0R (split) → paired (0L,0R)
      final m = buildSpreadMapping(
        pageCount: 1,
        doublePages: true,
        splitWide: true,
        splitInvert: false,
        isWide: wideSet({0}),
      );
      expect(m.length, 1);
      expect(m.entries[0].isPair, isTrue);
      expect(m.entries[0].first.half, PageHalf.left);
      expect(m.entries[0].second!.half, PageHalf.right);
      expect(m.entries[0].primaryRaw, 0);
    });

    test('portrait + split-wide pairs shift alignment deterministically', () {
      // pages: 0(portrait) [1 wide]  → units 0, 1L, 1R → (0,1L) (1R)
      final m = buildSpreadMapping(
        pageCount: 2,
        doublePages: true,
        splitWide: true,
        splitInvert: false,
        isWide: wideSet({1}),
      );
      expect(m.length, 2);
      expect(m.entries[0],
          const SpreadEntry(PageUnit(0), PageUnit(1, half: PageHalf.left)));
      expect(m.entries[1],
          const SpreadEntry(PageUnit(1, half: PageHalf.right)));
      expect(primaries(m), [0, 1]);
    });
  });

  group('automatic (orientation resolved by caller)', () {
    test('landscape → caller passes doublePages:true → pairs', () {
      final m = buildSpreadMapping(
        pageCount: 4,
        doublePages: true, // caller resolved automatic+landscape
        splitWide: false,
        splitInvert: false,
        isWide: wideSet(noWide),
      );
      expect(m.length, 2);
      expect(primaries(m), [0, 2]);
    });

    test('portrait → caller passes doublePages:false → identity', () {
      final m = buildSpreadMapping(
        pageCount: 4,
        doublePages: false, // caller resolved automatic+portrait
        splitWide: false,
        splitInvert: false,
        isWide: wideSet(noWide),
      );
      expect(m.length, 4);
      expect(primaries(m), [0, 1, 2, 3]);
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
        {'double': false, 'split': true, 'wide': {1, 4}},
        {'double': true, 'split': false, 'wide': {2}},
        {'double': true, 'split': true, 'wide': {3}},
        {'double': true, 'split': false, 'wide': {0, 5}},
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
            expect(raw, greaterThanOrEqualTo(prev),
                reason: 'primaries monotonic for $c invert=$invert');
            prev = raw;
          }
          // (3) rawToDisplay lands on a spread that actually CONTAINS the raw.
          for (var raw = 0; raw < 6; raw++) {
            final d = m.rawToDisplay(raw);
            expect(d, inInclusiveRange(0, m.length - 1), reason: '$c raw=$raw');
            final e = m.entries[d];
            expect(e.first.raw == raw || e.second?.raw == raw, isTrue,
                reason: 'rawToDisplay($raw) must contain it for $c');
          }
        }
      }
    });
  });
}
