// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';

/// Maps the previous/next chapter actions onto the two chapter buttons that
/// flank the horizontal seek bar.
///
/// In RTL the story advances leftward, so the left-pointing glyph has to move
/// forward or it contradicts every other control on screen. Komikku's
/// ChapterNavigator performs the same swap; its vertical navigator does not,
/// and neither do we — the side seekbar only renders in vertical-scroll modes,
/// which are never RTL.
///
/// A null callback means there is no chapter that way; the button renders
/// disabled.
({VoidCallback? leading, VoidCallback? trailing}) chapterNavCallbacks({
  required bool isRtl,
  required VoidCallback? onPreviousChapter,
  required VoidCallback? onNextChapter,
}) =>
    isRtl
        ? (leading: onNextChapter, trailing: onPreviousChapter)
        : (leading: onPreviousChapter, trailing: onNextChapter);
