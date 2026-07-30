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
}
