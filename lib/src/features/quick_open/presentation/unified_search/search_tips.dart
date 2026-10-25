// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/motion/reduce_motion.dart';

Future<void> showSearchTips(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      final body = Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        color: scheme.onSurfaceVariant,
      );
      Text tip(String Function(Object) format, String example) {
        const sentinel = '\u{0}';
        final template = format(sentinel);
        final parts = template.split(sentinel);
        if (parts.length < 2) {
          return Text(template.replaceAll(sentinel, example), style: body);
        }
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: parts.first),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    example,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
              if (parts.length > 1) TextSpan(text: parts.last),
            ],
          ),
          style: body,
        );
      }

      final l10n = context.l10n;
      return AlertDialog(
        title: Text(l10n.searchTips),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Text(l10n.searchTipsPlainWords, style: body),
            tip(l10n.searchTipsField, 'author:oda'),
            tip(l10n.searchTipsExclude, '-tag:dropped'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.close),
          ),
        ],
      );
    },
    animationStyle: context.motionStyle,
  );
}
