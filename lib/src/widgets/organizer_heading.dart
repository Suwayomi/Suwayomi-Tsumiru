// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../utils/extensions/custom_extensions.dart';

/// Compact section header (24dp/tight padding, primary-tinted `labelLarge`)
/// shared by the library organizer's tabs and the tri-state filter rows.
class OrganizerHeading extends StatelessWidget {
  const OrganizerHeading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Text(
        text,
        style: context.theme.textTheme.labelLarge?.copyWith(
          color: context.theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Explanatory line under an [OrganizerHeading], for controls whose gesture
/// isn't obvious.
class OrganizerHint extends StatelessWidget {
  const OrganizerHint(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Text(
        text,
        style: context.theme.textTheme.bodySmall?.copyWith(
          color: context.theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
