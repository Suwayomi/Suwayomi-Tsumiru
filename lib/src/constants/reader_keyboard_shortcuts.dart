// Copyright (c) 2023 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NextScrollIntent extends Intent {}

class NextChapterIntent extends Intent {}

class PreviousScrollIntent extends Intent {}

class PreviousChapterIntent extends Intent {}

class HideQuickOpenIntent extends Intent {}

class ViewportScrollForwardIntent extends Intent {}

class ViewportScrollBackwardIntent extends Intent {}

ShortcutManager readerShortcutManager(Axis scrollDirection,
        {bool isRtl = false}) =>
    ShortcutManager(
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.space): NextScrollIntent(),
        const SingleActivator(LogicalKeyboardKey.space, shift: true):
            PreviousScrollIntent(),
        // RTL manga reads right→left, so the physical left key advances.
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            isRtl ? NextScrollIntent() : PreviousScrollIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA):
            isRtl ? NextScrollIntent() : PreviousScrollIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            isRtl ? PreviousScrollIntent() : NextScrollIntent(),
        const SingleActivator(LogicalKeyboardKey.keyD):
            isRtl ? PreviousScrollIntent() : NextScrollIntent(),
        const SingleActivator(LogicalKeyboardKey.comma):
            PreviousChapterIntent(),
        const SingleActivator(LogicalKeyboardKey.period): NextChapterIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            scrollDirection == Axis.vertical
                ? ViewportScrollBackwardIntent()
                : NextChapterIntent(),
        const SingleActivator(LogicalKeyboardKey.keyW):
            scrollDirection == Axis.vertical
                ? ViewportScrollBackwardIntent()
                : NextChapterIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            scrollDirection == Axis.vertical
                ? ViewportScrollForwardIntent()
                : PreviousChapterIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS):
            scrollDirection == Axis.vertical
                ? ViewportScrollForwardIntent()
                : PreviousChapterIntent(),
        const SingleActivator(LogicalKeyboardKey.pageUp):
            ViewportScrollBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.pageDown):
            ViewportScrollForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): HideQuickOpenIntent(),
      },
    );
