// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/reader_keyboard_shortcuts.dart';

void main() {
  test('vertical and RTL binding map', () {
    final manager = readerShortcutManager(Axis.vertical);
    expect(
      manager.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowDown)],
      isA<ViewportScrollForwardIntent>(),
    );
    expect(
      manager.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowUp)],
      isA<ViewportScrollBackwardIntent>(),
    );
    expect(
      manager.shortcuts[const SingleActivator(LogicalKeyboardKey.pageDown)],
      isA<ViewportScrollForwardIntent>(),
    );
    expect(
      manager.shortcuts[const SingleActivator(LogicalKeyboardKey.pageUp)],
      isA<ViewportScrollBackwardIntent>(),
    );
    expect(
      manager.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowLeft)],
      isA<PreviousScrollIntent>(),
    );
    expect(
      manager.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowRight)],
      isA<NextScrollIntent>(),
    );
    expect(
      manager.shortcuts[const SingleActivator(LogicalKeyboardKey.comma)],
      isA<PreviousChapterIntent>(),
    );
    expect(
      manager.shortcuts[const SingleActivator(LogicalKeyboardKey.period)],
      isA<NextChapterIntent>(),
    );

    // RTL flips left/right only.
    final rtl = readerShortcutManager(Axis.horizontal, isRtl: true);
    expect(
      rtl.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowLeft)],
      isA<NextScrollIntent>(),
    );
    expect(
      rtl.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowRight)],
      isA<PreviousScrollIntent>(),
    );
    expect(
      rtl.shortcuts[const SingleActivator(LogicalKeyboardKey.keyA)],
      isA<NextScrollIntent>(),
    );
    expect(
      rtl.shortcuts[const SingleActivator(LogicalKeyboardKey.keyD)],
      isA<PreviousScrollIntent>(),
    );

    // LTR keeps left=previous/right=next.
    final ltr = readerShortcutManager(Axis.horizontal, isRtl: false);
    expect(
      ltr.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowLeft)],
      isA<PreviousScrollIntent>(),
    );
    expect(
      ltr.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowRight)],
      isA<NextScrollIntent>(),
    );

    // And RTL never touches vertical scroll.
    final verticalRtl = readerShortcutManager(Axis.vertical, isRtl: true);
    expect(
      verticalRtl.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowUp)],
      isA<ViewportScrollBackwardIntent>(),
    );
    expect(
      verticalRtl.shortcuts[const SingleActivator(
        LogicalKeyboardKey.arrowDown,
      )],
      isA<ViewportScrollForwardIntent>(),
    );
  });
}
