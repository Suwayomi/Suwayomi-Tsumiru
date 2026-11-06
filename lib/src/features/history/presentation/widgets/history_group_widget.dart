// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:material_ui/material_ui.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_page_frame.dart';
import '../../domain/history_group.dart';
import '../../domain/history_item.dart';
import 'history_item_tile.dart';

class HistoryGroupWidget extends StatelessWidget {
  const HistoryGroupWidget({
    super.key,
    required this.group,
  });

  final HistoryGroup group;

  @override
  Widget build(BuildContext context) {
    if (group.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HistoryGroupHeader(group: group),
        ...group.items.map((HistoryItemDto item) => HistoryItemTile(
              item: item,
            )),
        const SizedBox(height: 16),
      ],
    );
  }
}

class HistoryGroupHeader extends StatelessWidget {
  const HistoryGroupHeader({super.key, required this.group, this.first = false});

  final HistoryGroup group;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 12,
      ).onDesktopPageLine(context, top: first),
      child: Row(
        children: [
          Text(
            group.getLocalizedTitle(context),
            style: context.theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: context.theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: context.theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${group.itemCount}',
              style: context.theme.textTheme.labelSmall?.copyWith(
                color: context.theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
}
