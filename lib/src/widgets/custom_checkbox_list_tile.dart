// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';

import '../utils/extensions/custom_extensions.dart';

/// Compact bool? row; mutation flows through onChanged rather than a concrete provider type.
class CustomCheckboxListTile extends ConsumerWidget {
  const CustomCheckboxListTile({
    super.key,
    required this.title,
    required this.provider,
    required this.onChanged,
    this.initial = true,
  });
  final String title;
  final ProviderListenable<bool?> provider;
  final ValueChanged<bool?> onChanged;

  /// What an unset preference reads as.
  final bool initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checked = ref.watch(provider) ?? initial;
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
}
