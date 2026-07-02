// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../utils/extensions/custom_extensions.dart';

/// A small rounded-square play button overlaid on / beside a library cover that
/// jumps straight into the next unread chapter: a filled icon
/// button with the `small` shape, a `primaryContainer` fill, and a play glyph.
/// Its own [InkWell] wins the tap over the cover's gesture, so opening the
/// reader never also opens the details page.
class ContinueReadingButton extends StatelessWidget {
  const ContinueReadingButton({
    super.key,
    required this.onPressed,
    this.size = 32,
    this.iconSize = 20,
  });

  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: Icon(
            Icons.play_arrow_rounded,
            size: iconSize,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
