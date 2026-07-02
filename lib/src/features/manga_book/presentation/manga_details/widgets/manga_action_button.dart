// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../../utils/extensions/custom_extensions.dart';

/// Compact icon-over-label action button for the manga-details action row: a
/// weight-1 TextButton wrapping a centered Column of a 20dp icon, a 4dp gap and
/// a 12sp centered label. Active items use the primary color; the rest recede.
///
/// Put each in an [Expanded] so the row's items share width evenly.
class MangaActionButton extends StatelessWidget {
  const MangaActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.active = false,
  });

  /// Usually an [Icon]; may be any widget (e.g. a progress spinner). Its colour
  /// and 20dp size are applied via [IconTheme].
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;

  /// Highlight (primary colour) when the action's state is "on".
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    final color = active ? cs.primary : cs.onSurfaceVariant;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme.merge(
            data: IconThemeData(size: 20, color: color),
            child: icon,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }
}
