// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import 'library_manga_display.dart';
import 'library_manga_filter.dart';
import 'library_manga_group.dart';
import 'library_manga_sort_tile.dart';
import '../../../../tracking/data/tracker_repository.dart';

/// Sort-key display order. Kept separate from the
/// `MangaSort` enum declaration because that is persisted by index.
const List<MangaSort> _sortDisplayOrder = [
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
      child: _OrganizerBody(hasTrackers: hasTrackers),
    );
  }
}

/// The organizer sizes itself to the ACTIVE tab's content (up to 72% of the
/// screen, then scrolls), animating the height as you move between tabs — so
/// the sheet is short for Group and taller for Sort instead of a fixed panel.
class _OrganizerBody extends StatelessWidget {
  const _OrganizerBody({required this.hasTrackers});
  final bool hasTrackers;

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    final tabs = <Widget>[
      const LibraryMangaFilter(),
      // Sort — display order: Alphabetical, Total
      // chapters, Last read, Last update, Unread, Latest chapter, Chapter fetch
      // date, Date added, [Tracker score], Random. (Enum declaration order
      // differs because prefs are stored by index.)
      ListView(
        shrinkWrap: true,
        children: [
          for (final sortType in _sortDisplayOrder)
            if (sortType != MangaSort.trackerScore || hasTrackers)
              LibraryMangaSortTile(sortType: sortType),
        ],
      ),
      const LibraryMangaDisplay(),
      const LibraryMangaGroup(),
    ];
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            // Non-scrollable tabs: fill alignment keeps the selection underline
            // aligned under every tab (the global theme defaults to
            // TabAlignment.center for the scrollable category tabs).
            tabAlignment: TabAlignment.fill,
            tabs: [
              Tab(text: context.l10n.filter),
              Tab(text: context.l10n.sort),
              Tab(text: context.l10n.display),
              Tab(text: context.l10n.group),
            ],
          ),
          // Rebuild + animate the height whenever the active tab changes.
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) => AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: tabs[controller.index],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
