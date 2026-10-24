// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/organizer_heading.dart';
import '../../../../tracking/data/tracker_repository.dart';
import 'library_manga_badges.dart';
import 'library_manga_display.dart';
import 'library_manga_filter.dart';
import 'library_manga_group.dart';
import 'library_manga_sort_tile.dart';

/// Display order is separate from MangaSort because enum indices are persisted.
const List<MangaSort> librarySortDisplayOrder = [
  MangaSort.alphabetical,
  MangaSort.rating,
  MangaSort.totalChapters,
  MangaSort.lastRead,
  MangaSort.lastUpdate,
  MangaSort.unread,
  MangaSort.lastChapterDate,
  MangaSort.lastUpdated,
  MangaSort.dateAdded,
  MangaSort.trackerScore,
  MangaSort.random,
];

class LibraryMangaOrganizer extends ConsumerWidget {
  const LibraryMangaOrganizer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTrackers =
        ref.watch(loggedInTrackersProvider).value?.isNotEmpty ?? false;
    return DefaultTabController(
      length: 4,
      animationDuration: context.reduceMotion
          ? Duration.zero
          : kTabScrollDuration,
      child: _OrganizerBody(hasTrackers: hasTrackers),
    );
  }
}

/// Sizes to the active tab, capped at 72% of screen height.
class _OrganizerBody extends StatelessWidget {
  const _OrganizerBody({required this.hasTrackers});
  final bool hasTrackers;

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    final tabs = <Widget>[
      const LibraryMangaFilter(),
      ListView(
        shrinkWrap: true,
        children: [
          for (final sortType in librarySortDisplayOrder)
            if (sortType != MangaSort.trackerScore || hasTrackers)
              LibraryMangaSortTile(sortType: sortType),
        ],
      ),
      _DisplayTab(),
      const LibraryMangaGroup(),
    ];
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            // Fill alignment overrides the theme's centered alignment for scrollable tabs.
            tabAlignment: TabAlignment.fill,
            tabs: [
              Tab(text: context.l10n.filter),
              Tab(text: context.l10n.sort),
              Tab(text: context.l10n.display),
              Tab(text: context.l10n.group),
            ],
          ),
          // Flexible also respects space taken by siblings such as the updating banner.
          Flexible(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final content = ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: tabs[controller.index],
                );
                if (context.reduceMotion) return content;
                return AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: content,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// One outer scrollable owns both nested display and badge lists.
class _DisplayTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        const LibraryMangaDisplay(scrollable: false),
        OrganizerHeading(context.l10n.badges),
        const LibraryMangaBadges(scrollable: false),
      ],
    );
  }
}
