// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/theme/brand.dart';
import '../brand_page_seekbar.dart';

/// The reader's floating vertical seek bar content, shown in webtoon/vertical
/// mode.
///
/// This widget renders the seek-bar column (skip-to-start button ↑ + track +
/// skip-to-end button ↓). It does **not** own a [Positioned] — the caller
/// ([ReaderChrome]) is responsible for wrapping it in a [Positioned] whose
/// [top] and [bottom] are derived from the measured [ChromeExtents], so the
/// seekbar never overlaps the top or bottom chrome bars.
class ReaderSideSeekBar extends StatelessWidget {
  const ReaderSideSeekBar({
    super.key,
    required this.currentIndex,
    required this.pageCount,
    required this.onChanged,
  });

  final int currentIndex;

  /// Total page count (may be from infinity-scroll total or chapter page count).
  final int pageCount;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final navSurface = readerNavSurface(context.theme.colorScheme);
    final lastPage = pageCount - 1;

    return Column(
      children: [
        // Jump to the start of this chapter — Komikku skip-previous
        // glyph rotated to point up.
        BrandFilledCircleButton(
          icon: Icons.skip_previous_rounded,
          quarterTurns: 1,
          color: navSurface,
          onPressed: () => onChanged(0),
        ),
        const Gap(8),
        Expanded(
          child: BrandPageSeekBar(
            currentValue: currentIndex,
            maxValue: pageCount,
            onChanged: onChanged,
            axis: Axis.vertical,
            capsuleColor: navSurface,
          ),
        ),
        const Gap(8),
        // Jump to the end of this chapter — Komikku skip-next
        // glyph rotated to point down.
        BrandFilledCircleButton(
          icon: Icons.skip_next_rounded,
          quarterTurns: 1,
          color: navSurface,
          onPressed: () => onChanged(lastPage),
        ),
      ],
    );
  }
}
