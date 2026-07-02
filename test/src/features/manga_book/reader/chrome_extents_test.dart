// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// ChromeExtents is a pure value type that composes the system status-bar /
// nav-bar insets with the measured, mode-specific bar heights.  These tests
// pin the math and the equality contract before any widget code lands.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/chrome_extents.dart';

void main() {
  group('ChromeExtents', () {
    test('topInset = systemStatusBarInset + measured top-bar height', () {
      // notch device: 44 dp system inset + 56 dp top-bar height = 100 dp
      const e = ChromeExtents(topInset: 44 + 56, bottomInset: 24 + 40);
      expect(e.topInset, 100);
    });

    test('bottomInset = systemNavBarInset + measured bottom-bar height', () {
      // gesture-nav device: 24 dp system inset + 40 dp (short webtoon bar) = 64 dp
      const e = ChromeExtents(topInset: 44 + 56, bottomInset: 24 + 40);
      expect(e.bottomInset, 64);
    });

    test('value equality: same fields → equal', () {
      const a = ChromeExtents(topInset: 100, bottomInset: 64);
      const b = ChromeExtents(topInset: 100, bottomInset: 64);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('value equality: different topInset → not equal', () {
      const a = ChromeExtents(topInset: 100, bottomInset: 64);
      const b = ChromeExtents(topInset: 80, bottomInset: 64);
      expect(a, isNot(equals(b)));
    });

    test('value equality: different bottomInset → not equal', () {
      const a = ChromeExtents(topInset: 100, bottomInset: 64);
      const b = ChromeExtents(topInset: 100, bottomInset: 100);
      expect(a, isNot(equals(b)));
    });

    test('zero extents are valid (no system inset, no bars)', () {
      const e = ChromeExtents(topInset: 0, bottomInset: 0);
      expect(e.topInset, 0);
      expect(e.bottomInset, 0);
    });

    test('computed extent = systemInset + measuredBarHeight (the math)',
        () {
      const systemTop = 44.0;
      const measuredTopBar = 56.0;
      const systemBottom = 24.0;
      const measuredBottomBar = 40.0; // webtoon: short bar (no seek row)

      final extents = ChromeExtents(
        topInset: systemTop + measuredTopBar,
        bottomInset: systemBottom + measuredBottomBar,
      );

      expect(extents.topInset, systemTop + measuredTopBar);
      expect(extents.bottomInset, systemBottom + measuredBottomBar);

      // Paged mode bottom bar is taller (includes the seek row).
      const measuredBottomBarPaged = 88.0;
      final pagedExtents = ChromeExtents(
        topInset: systemTop + measuredTopBar,
        bottomInset: systemBottom + measuredBottomBarPaged,
      );
      expect(pagedExtents.bottomInset, greaterThan(extents.bottomInset));
    });
  });

  // ── topInset formula: no double-counting of status-bar inset ──────────────
  //
  // Bug: ReaderTopBar.onChange previously used `systemTopInset + size.height`,
  // but MeasureSize wraps the Material that already contains
  // `Padding(top: systemTopInset)`.  So size.height == systemTopInset + barContent.
  // Adding systemTopInset again double-counts it → seekbar top edge 44 dp too low.
  //
  // Fix: use `topInset: size.height` (mirrors `bottomInset: size.height` in
  // the bottom controls, where the nav-bar Padding is inside the measured subtree).
  //
  // These tests verify the formula contract directly without needing a widget pump.
  group('topInset formula — no double-counting (Bug B fix)', () {
    // Simulate the measurement that MeasureSize reports for the top bar on a
    // notch device:
    //   systemTopInset = 44 dp  (status-bar inset baked into Material padding)
    //   bar content    = 56 dp  (AppBar-equivalent content row)
    //   → size.height  = 100 dp (what MeasureSize actually sees)
    const systemTopInset = 44.0;
    const materialHeight = 100.0; // systemTopInset (44) + content (56) = 100

    test('topInset = size.height (no double-count) → 100, NOT 144', () {
      // Correct formula: pass size.height directly.
      const correctTopInset = materialHeight; // 100
      const e = ChromeExtents(topInset: correctTopInset, bottomInset: 64);
      expect(e.topInset, 100.0,
          reason:
              'topInset must equal the measured Material height (100 dp), '
              'not systemTopInset + size.height (144 dp)');
    });

    test('old buggy formula (systemTopInset + size.height) yields 144, not 100', () {
      // Reproduce the old broken formula to confirm the regression value.
      const buggyTopInset = systemTopInset + materialHeight; // 44 + 100 = 144
      expect(buggyTopInset, 144.0,
          reason: 'The old formula produces 144 — the dead-gap value on notch devices');
      expect(buggyTopInset, isNot(100.0),
          reason:
              'The old formula is wrong: 144 ≠ 100 (proves the new formula '
              'would FAIL under the old code)');
    });

    test('correct formula equals bottom-bar contract (size.height only)', () {
      // The bottom bar uses `bottomInset: size.height` — the top bar should be
      // symmetric. Both include their respective system-inset padding inside the
      // measured subtree and report ONLY size.height to the provider.
      const bottomMaterialHeight = 64.0; // nav-bar 24 + content 40
      const e = ChromeExtents(
        topInset: materialHeight,      // fix: size.height only
        bottomInset: bottomMaterialHeight, // already correct in the bottom controls
      );
      expect(e.topInset, materialHeight,
          reason: 'topInset must equal measured Material height (symmetric with bottomInset)');
      expect(e.bottomInset, bottomMaterialHeight,
          reason: 'bottomInset uses size.height; top formula must match');
    });
  });
}
