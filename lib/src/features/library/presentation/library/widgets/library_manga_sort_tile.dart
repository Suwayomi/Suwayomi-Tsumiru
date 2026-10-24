// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../controller/library_controller.dart';

class LibraryMangaSortTile extends ConsumerWidget {
  const LibraryMangaSortTile({
    super.key,
    required this.sortType,
  });
  final MangaSort sortType;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sortedBy = ref.watch(libraryMangaSortProvider);
    final sortedDirection =
        ref.watch(libraryMangaSortDirectionProvider).ifNull(true);
    final isSelected = sortType == sortedBy;
    final primary = context.theme.colorScheme.primary;

    // Selecting Random again re-rolls; its comparator ignores sort direction.
    if (sortType == MangaSort.random) {
      final seed = ref.watch(librarySortRandomSeedProvider) ??
          DBKeys.librarySortRandomSeed.initial as int;
      return _CompactSortRow(
        label: sortType.toLocale(context),
        leading: isSelected
            ? Icon(FluentIcons.arrow_shuffle_24_regular, color: primary)
            : null,
        onTap: isSelected
            ? () => ref
                .read(librarySortRandomSeedProvider.notifier)
                .update(seed + 1)
            : () =>
                ref.read(libraryMangaSortProvider.notifier).update(sortType),
      );
    }

    return _CompactSortRow(
      label: sortType.toLocale(context),
      leading: isSelected
          ? Icon(
              sortedDirection
                  ? FluentIcons.arrow_sort_up_24_regular
                  : FluentIcons.arrow_sort_down_24_regular,
              color: primary,
            )
          : null,
      onTap: () {
        if (isSelected) {
          ref
              .read(libraryMangaSortDirectionProvider.notifier)
              .update(!sortedDirection);
        } else {
          ref.read(libraryMangaSortProvider.notifier).update(sortType);
        }
      },
    );
  }
}

class _CompactSortRow extends StatelessWidget {
  const _CompactSortRow({
    required this.label,
    required this.onTap,
    this.leading,
  });
  final String label;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: leading ?? const SizedBox.shrink(),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Text(
                label,
                style: context.theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
