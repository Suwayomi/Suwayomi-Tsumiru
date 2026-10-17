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
