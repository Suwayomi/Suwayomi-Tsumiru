// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// continuousHorizontalLTR/RTL used to be pure paged-mode aliases (routed to
// MultiChapterPagedReaderMode) — isPagedReaderMode said `true` for them to
// match. Now that reader_screen.dart routes them to the real continuous
// scroll widget (MultiChapterContinuousReaderMode, scrollDirection:
// Axis.horizontal), isPagedReaderMode must say `false`, so gesture routing
// and the bottom controls agree with what's actually on screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/utils/reader_mode_kind.dart';

void main() {
  group('defaultNavigationFor', () {
    test('horizontal modes (paged or continuous) get right-and-left zones', () {
      expect(
        defaultNavigationFor(ReaderMode.singleHorizontalLTR),
        ReaderNavigationLayout.rightAndLeft,
      );
      expect(
        defaultNavigationFor(ReaderMode.singleHorizontalRTL),
        ReaderNavigationLayout.rightAndLeft,
      );
      expect(
        defaultNavigationFor(ReaderMode.continuousHorizontalLTR),
        ReaderNavigationLayout.rightAndLeft,
      );
      expect(
        defaultNavigationFor(ReaderMode.continuousHorizontalRTL),
        ReaderNavigationLayout.rightAndLeft,
      );
    });
  });
}
