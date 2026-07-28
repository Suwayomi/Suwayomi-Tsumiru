// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/custom_checkbox_list_tile.dart';
import '../../../../../widgets/manga_cover/providers/manga_cover_providers.dart';
import '../../../../../widgets/organizer_heading.dart';

/// The "Badges" tab inside [LibraryMangaOrganizer]: everything that feeds
/// `MangaBadgesRow` and the cover overlays.
class LibraryMangaBadges extends ConsumerWidget {
  const LibraryMangaBadges({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadMode =
        ref.watch(unreadBadgeStyleProvider) ?? UnreadBadgeMode.count;

    return ListView(
      shrinkWrap: true,
      children: [
        OrganizerHeading(context.l10n.unreadBadgeMode),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final mode in UnreadBadgeMode.values)
                FilterChip(
                  selected: unreadMode == mode,
                  showCheckmark: false,
                  label: Text(mode.toLocale(context)),
                  onSelected: (_) =>
                      ref.read(unreadBadgeStyleProvider.notifier).update(mode),
                ),
            ],
          ),
        ),
        // Server-side download count.
        CustomCheckboxListTile(
          title: context.l10n.downloaded,
          provider: downloadedBadgeProvider,
          onChanged: ref.read(downloadedBadgeProvider.notifier).update,
        ),
        // This device's offline downloads — a subset of the above.
        CustomCheckboxListTile(
          title: context.l10n.onDevice,
          provider: onDeviceBadgeProvider,
          onChanged: ref.read(onDeviceBadgeProvider.notifier).update,
        ),
        CustomCheckboxListTile(
          title: context.l10n.readProgressBar,
          provider: readProgressBarProvider,
          onChanged: ref.read(readProgressBarProvider.notifier).update,
        ),
        CustomCheckboxListTile(
          title: context.l10n.continueReadingButton,
          provider: showContinueReadingButtonProvider,
          onChanged:
              ref.read(showContinueReadingButtonProvider.notifier).update,
        ),
        // Covers Local Source too, as a folder glyph.
        CustomCheckboxListTile(
          title: context.l10n.sourceBadge,
          provider: sourceBadgeProvider,
          onChanged: ref.read(sourceBadgeProvider.notifier).update,
        ),
        // Drawn as the language's flag emoji.
        CustomCheckboxListTile(
          title: context.l10n.languageBadge,
          provider: languageBadgeProvider,
          onChanged: ref.read(languageBadgeProvider.notifier).update,
        ),
        OrganizerHeading(context.l10n.badgeLayout),
        OrganizerHint(context.l10n.badgeLayoutHint),
        const _BadgeLayoutList(),
      ],
    );
  }
}

/// Drag-to-reorder list of every cover badge, each with an inline button that
/// flips it between the cover's top-left and top-right clusters.
class _BadgeLayoutList extends ConsumerWidget {
  const _BadgeLayoutList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(libraryBadgeLayoutProvider);

    // onReorderItem already accounts for the removal, unlike the deprecated
    // onReorder, so newIndex is the final resting slot.
    void move(int oldIndex, int newIndex) {
      final ids = layout.map((p) => p.badge.id).toList();
      ids.insert(newIndex, ids.removeAt(oldIndex));
      ref.read(badgeOrderProvider.notifier).update(ids);
    }

    void toggleSide(LibraryBadge badge, BadgeSide current) {
      final right = layout
          .where((p) => p.side == BadgeSide.right)
          .map((p) => p.badge.id)
          .toSet();
      if (current == BadgeSide.right) {
        right.remove(badge.id);
      } else {
        right.add(badge.id);
      }
      ref.read(badgeRightSideProvider.notifier).update(right.toList());
    }

    return ReorderableListView(
      // Nested inside the organizer's own ListView, which does the scrolling.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: move,
      children: [
        for (var i = 0; i < layout.length; i++)
          _BadgeLayoutRow(
            key: ValueKey(layout[i].badge.id),
            index: i,
            badge: layout[i].badge,
            side: layout[i].side,
            onToggleSide: () => toggleSide(layout[i].badge, layout[i].side),
          ),
      ],
    );
  }
}

class _BadgeLayoutRow extends StatelessWidget {
  const _BadgeLayoutRow({
    super.key,
    required this.index,
    required this.badge,
    required this.side,
    required this.onToggleSide,
  });

  final int index;
  final LibraryBadge badge;
  final BadgeSide side;
  final VoidCallback onToggleSide;

  @override
  Widget build(BuildContext context) {
    final isRight = side == BadgeSide.right;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Explicit handle, so the side button stays tappable instead of
          // starting a drag.
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Icon(Icons.drag_handle_rounded),
            ),
          ),
          Expanded(
            child: Text(
              badge.toLocale(context),
              style: context.theme.textTheme.bodyMedium,
            ),
          ),
          IconButton(
            tooltip: isRight
                ? context.l10n.badgeMoveToLeft
                : context.l10n.badgeMoveToRight,
            onPressed: onToggleSide,
            icon: Icon(
              isRight
                  ? Icons.format_align_right_rounded
                  : Icons.format_align_left_rounded,
            ),
          ),
        ],
      ),
    );
  }
}
