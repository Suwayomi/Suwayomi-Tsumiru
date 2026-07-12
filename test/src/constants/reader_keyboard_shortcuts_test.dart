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
  test('vertical mode maps arrow up/down to viewport scroll intents', () {
    final manager = readerShortcutManager(Axis.vertical);
    expect(manager.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowDown)],
        isA<ViewportScrollForwardIntent>());
    expect(manager.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowUp)],
        isA<ViewportScrollBackwardIntent>());
    expect(manager.shortcuts[const SingleActivator(LogicalKeyboardKey.pageDown)],
        isA<ViewportScrollForwardIntent>());
    expect(manager.shortcuts[const SingleActivator(LogicalKeyboardKey.pageUp)],
        isA<ViewportScrollBackwardIntent>());
  });

  test('vertical mode: left/right skim pages, comma/period change chapter',
      () {
    final m = readerShortcutManager(Axis.vertical);
    expect(m.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowLeft)],
        isA<PreviousScrollIntent>());
    expect(m.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowRight)],
        isA<NextScrollIntent>());
    expect(m.shortcuts[const SingleActivator(LogicalKeyboardKey.comma)],
        isA<PreviousChapterIntent>());
    expect(m.shortcuts[const SingleActivator(LogicalKeyboardKey.period)],
        isA<NextChapterIntent>());
  });

  test('RTL flips left/right: left advances, right goes back', () {
    final m = readerShortcutManager(Axis.horizontal, isRtl: true);
    expect(m.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowLeft)],
        isA<NextScrollIntent>());
    expect(m.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowRight)],
        isA<PreviousScrollIntent>());
    expect(m.shortcuts[const SingleActivator(LogicalKeyboardKey.keyA)],
        isA<NextScrollIntent>());
    expect(m.shortcuts[const SingleActivator(LogicalKeyboardKey.keyD)],
        isA<PreviousScrollIntent>());
  });

  test('LTR keeps left=previous/right=next; RTL leaves up/down alone', () {
    final ltr = readerShortcutManager(Axis.horizontal, isRtl: false);
    expect(ltr.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowLeft)],
        isA<PreviousScrollIntent>());
    expect(ltr.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowRight)],
        isA<NextScrollIntent>());

    // The RTL flip must only touch left/right, never vertical scroll.
    final rtl = readerShortcutManager(Axis.vertical, isRtl: true);
    expect(rtl.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowUp)],
        isA<ViewportScrollBackwardIntent>());
    expect(rtl.shortcuts[const SingleActivator(LogicalKeyboardKey.arrowDown)],
        isA<ViewportScrollForwardIntent>());
  });
}
