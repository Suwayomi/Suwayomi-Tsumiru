// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../utils/extensions/custom_extensions.dart';

/// Tri-state filter tile used across the library and chapter filter sheets.
///
/// Tristate cycle on tap: `null` (ignore) → `true` (include / require) →
/// `false` (exclude) → `null`. This matches the tri-state filter convention
/// users expect: the default empty state means "do not filter" and the two
/// active states clearly distinguish include from exclude with different icons.
///
/// In binary mode (`tristate: false`) the widget falls back to Flutter's
/// `CheckboxListTile`, which is what existing display-preference callers
/// (e.g. badge toggles) rely on.
class CustomCheckboxListTile<NotifierT extends AutoDisposeNotifier<bool?>>
    extends ConsumerWidget {
  const CustomCheckboxListTile({
    super.key,
    required this.title,
    required this.provider,
    required this.onChanged,
    this.tristate = true,
  });
  final String title;
  final AutoDisposeNotifierProvider<NotifierT, bool?> provider;
  final ValueChanged<bool?> onChanged;
  final bool tristate;

  static bool? _nextValue(bool? current) {
    if (current == null) return true;
    if (current == true) return false;
    return null;
  }

  Widget _tristateLeading(BuildContext context, bool? value) {
    final activeColor = context.theme.colorScheme.primary;
    final excludeColor = context.theme.colorScheme.error;
    if (value == null) {
      return Icon(
        Icons.check_box_outline_blank_rounded,
        color: context.theme.unselectedWidgetColor,
      );
    } else if (value == true) {
      return Icon(Icons.check_box_rounded, color: activeColor);
    } else {
      return Icon(Icons.disabled_by_default_rounded, color: excludeColor);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final val = ref.watch(provider);
    if (!tristate) {
      // Compact binary row using the SAME 24px check icon as the tri-state
      // rows (not a Material Checkbox, whose ~48px forced tap target made the
      // Display badges tower over the filter rows). 24dp/10dp padding keeps the
      // whole organizer at one consistent density.
      final checked = val.ifNull(true) ?? false;
      return InkWell(
        onTap: () => onChanged(!checked),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Row(
            children: [
              Icon(
                checked
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                color: checked
                    ? context.theme.colorScheme.primary
                    : context.theme.unselectedWidgetColor,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: context.theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Compact tri-state row (24dp horizontal / 10dp vertical, icon + text)
    // rather than a full-height ListTile, so the filter sheet stays dense.
    return InkWell(
      onTap: () => onChanged(_nextValue(val)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          children: [
            _tristateLeading(context, val),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: context.theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
