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
import '../../../../../widgets/organizer_heading.dart';
import '../../../../tracking/data/tracker_repository.dart';
import '../../../domain/library_group.dart';
import '../controller/library_controller.dart';
import '../controller/library_grouping.dart';

/// The "Group" tab inside [LibraryMangaOrganizer]: what the library is bucketed
/// by, how those buckets are presented, and the per-group affordances (tab
/// strip, item counts, hidden categories).
class LibraryMangaGroup extends ConsumerWidget {
  const LibraryMangaGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        ref.watch(libraryGroupTypeProvider) ?? kDefaultLibraryGroupType;
    final style =
        ref.watch(libraryGroupStyleKeyProvider) ?? LibraryGroupStyle.tabs;
    final hasTrackers =
        ref.watch(loggedInTrackersProvider).value?.isNotEmpty ?? false;

    String label(int type) => switch (type) {
          LibraryGroup.byDefault => context.l10n.groupByDefault,
          LibraryGroup.byTag => context.l10n.groupByTag,
          LibraryGroup.bySource => context.l10n.groupBySource,
          LibraryGroup.byStatus => context.l10n.groupByStatus,
          LibraryGroup.byTrackStatus => context.l10n.groupByTrackStatus,
          LibraryGroup.byLanguage => context.l10n.groupByLanguage,
          _ => context.l10n.groupUngrouped,
        };

    final isGrouped = LibraryGroup.isGrouped(current);

    return ListView(
      shrinkWrap: true,
      children: [
        RadioGroup<int>(
          groupValue: current,
          onChanged: (val) =>
              ref.read(libraryGroupTypeProvider.notifier).update(val),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final type in LibraryGroup.all)
                // Track status needs a logged-in tracker to bucket by.
                if (type != LibraryGroup.byTrackStatus || hasTrackers)
                  RadioListTile<int>(value: type, title: Text(label(type))),
            ],
          ),
        ),
        // Ungrouped is a single flat list, so there are no groups to lay out.
        if (isGrouped) ...[
          OrganizerHeading(context.l10n.groupStyle),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final option in LibraryGroupStyle.values)
                  FilterChip(
                    selected: style == option,
                    showCheckmark: false,
                    label: Text(option.toLocale(context)),
                    onSelected: (_) => ref
                        .read(libraryGroupStyleKeyProvider.notifier)
                        .update(option),
                  ),
              ],
            ),
          ),
          // One modifier key per style — see `_groupedBody` in
          // library_screen.dart for how the four states combine.
          if (style == LibraryGroupStyle.tabs)
            CustomCheckboxListTile(
              title: context.l10n.categoryTabs,
              provider: categoryTabsProvider,
              onChanged: ref.read(categoryTabsProvider.notifier).update,
            )
          else
            CustomCheckboxListTile(
              title: context.l10n.sectionHeadersShowAllCategories,
              provider: sectionHeadersShowAllCategoriesProvider,
              onChanged: ref
                  .read(sectionHeadersShowAllCategoriesProvider.notifier)
                  .update,
            ),
          // Hidden categories only exist under the category grouping.
          if (current == LibraryGroup.byDefault)
            CustomCheckboxListTile(
              title: context.l10n.showHiddenCategories,
              provider: showHiddenCategoriesProvider,
              onChanged: ref.read(showHiddenCategoriesProvider.notifier).update,
            ),
          // Decorates whichever group label is on screen, tab or section.
          CustomCheckboxListTile(
            title: context.l10n.categoryNumberOfItems,
            provider: categoryNumberOfItemsProvider,
            onChanged: ref.read(categoryNumberOfItemsProvider.notifier).update,
          ),
        ],
      ],
    );
  }
}
