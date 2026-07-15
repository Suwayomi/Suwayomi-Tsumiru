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

class AutoScrollToggleIntent extends Intent {}

class AutoScrollFasterIntent extends Intent {}

class AutoScrollSlowerIntent extends Intent {}

class FirstPageIntent extends Intent {}

class LastPageIntent extends Intent {}

ShortcutManager readerShortcutManager(Axis scrollDirection,
        {bool isRtl = false, bool autoScrollSupported = false}) =>
    ShortcutManager(
      shortcuts: {
        // Space toggles auto-scroll only in vertical modes that actually mount
        // an auto-scroll engine; elsewhere it stays page-advance (and
        // Shift+Space page-back), so keyboard paging never goes dead.
        const SingleActivator(LogicalKeyboardKey.space):
            scrollDirection == Axis.vertical && autoScrollSupported
                ? AutoScrollToggleIntent()
                : NextScrollIntent(),
        const SingleActivator(LogicalKeyboardKey.space, shift: true):
            scrollDirection == Axis.vertical && autoScrollSupported
                ? AutoScrollToggleIntent()
                : PreviousScrollIntent(),
        if (scrollDirection == Axis.vertical && autoScrollSupported) ...{
          const SingleActivator(LogicalKeyboardKey.equal):
              AutoScrollFasterIntent(),
          const SingleActivator(LogicalKeyboardKey.numpadAdd):
              AutoScrollFasterIntent(),
          const SingleActivator(LogicalKeyboardKey.minus):
              AutoScrollSlowerIntent(),
          const SingleActivator(LogicalKeyboardKey.numpadSubtract):
              AutoScrollSlowerIntent(),
        },
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
        const SingleActivator(LogicalKeyboardKey.home): FirstPageIntent(),
        const SingleActivator(LogicalKeyboardKey.end): LastPageIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): HideQuickOpenIntent(),
      },
    );
