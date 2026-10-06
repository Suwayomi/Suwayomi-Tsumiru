// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../../utils/extensions/custom_extensions.dart';

class MissingChaptersListTile extends StatelessWidget {
  const MissingChaptersListTile({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.missingChapters(count);
    final color = context.theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(child: Divider(color: color)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                label,
                style: context.theme.textTheme.labelMedium?.copyWith(
                  color: color,
                ),
              ),
            ),
            Expanded(child: Divider(color: color)),
          ],
        ),
      ),
    );
  }
}

class MissingChaptersGridTile extends StatelessWidget {
  const MissingChaptersGridTile({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.missingChapters(count);
    final colors = context.theme.colorScheme;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.more_horiz_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: context.theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
