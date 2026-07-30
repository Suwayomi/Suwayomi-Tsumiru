// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/shell/update_banner_state.dart';
import '../../../../manga_book/data/updates/updates_repository.dart';
import '../../../../offline/data/server_reachability.dart';
import '../controller/library_controller.dart';
import '../controller/library_grouping.dart';
import '../controller/library_manga_list.dart';
import 'library_manga_grid_view.dart';

/// One section of the headers-style library.
typedef LibrarySection = ({int id, String name});

/// The "section headers" group style: one continuous scroll where every group
/// is introduced by a sticky header, instead of a tab per group.
///
/// The only writer of [libraryVisibleSectionProvider].
class LibrarySectionsView extends HookConsumerWidget {
  const LibrarySectionsView({
    super.key,
    required this.sections,
    required this.byCategory,
    this.showCounts = false,
  });

  final List<LibrarySection> sections;

  /// True for BY_DEFAULT, whose sections are categories and read from
  /// [categoryMangaListWithQueryAndFilterProvider]; false for every other group
  /// mode, which reads [groupedMangaListWithQueryAndFilterProvider].
  final bool byCategory;

  /// Append "(N)" to each header, honouring the same preference as the tabs.
  final bool showCounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One GlobalKey per section id, held in a hook so the tracker below keeps
    // following the same element across rebuilds. Pruned so a vanished section
    // can't leak its key.
    final headerKeys = useRef(<int, GlobalKey>{});
    for (final s in sections) {
      headerKeys.value.putIfAbsent(s.id, GlobalKey.new);
    }
    headerKeys.value.removeWhere((id, _) => !sections.any((s) => s.id == id));

    final scrollController = useScrollController();

    // Tracks which section is at the top of the viewport.
    useEffect(() {
      void trackVisibleSection() {
        if (!scrollController.hasClients) return;
        int? topId;
        double? topY;
        for (final entry in headerKeys.value.entries) {
          final box =
              entry.value.currentContext?.findRenderObject() as RenderBox?;
          if (box == null || !box.attached) continue;
          final y = box.localToGlobal(Offset.zero).dy;
          // The active pinned header sits at or just above the viewport's top
          // edge; of those, the largest y (closest to it) is the current one.
          if (y <= 1 && (topY == null || y > topY)) {
            topY = y;
            topId = entry.key;
          }
        }
        if (topId != null && topId != ref.read(libraryVisibleSectionProvider)) {
          ref.read(libraryVisibleSectionProvider.notifier).update(topId);
        }
      }

      scrollController.addListener(trackVisibleSection);
      // Seed after the first layout: no scroll event fires at the very top, so
      // the tracked section would otherwise stay null until the user scrolled.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) trackVisibleSection();
      });
      return () => scrollController.removeListener(trackVisibleSection);
      // Re-seed on section-count changes: a group appearing or disappearing
      // shifts what's on screen at the current offset.
    }, [scrollController, sections.length]);

    return RefreshIndicator(
      // No single group under the finger here, so pull runs a whole-library
      // source check — same rule the grouped tabs use.
      onRefresh: () async {
        // A pull means "try the server again" — drop the offline pin.
        ref.read(viewOfflineNowProvider.notifier).set(false);
        ref.read(serverUnreachableProvider.notifier).set(false);
        ref.read(updateOptimisticProvider.notifier).arm();
        unawaited(
          ref
              .read(updatesRepositoryProvider)
              .fetchUpdates()
              .catchError((Object _) {}),
        );
        ref.invalidate(libraryMangaListProvider);
        await ref.read(libraryMangaListProvider.future);
      },
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          for (final section in sections)
            _Section(
              key: ValueKey(section.id),
              headerKey: headerKeys.value[section.id]!,
              section: section,
              byCategory: byCategory,
              showCount: showCounts,
            ),
        ],
      ),
    );
  }
}

/// A header + its manga, as a [SliverMainAxisGroup] so the header un-pins
/// exactly when its own group scrolls away.
class _Section extends ConsumerWidget {
  const _Section({
    super.key,
    required this.headerKey,
    required this.section,
    required this.byCategory,
    required this.showCount,
  });

  final LibrarySection section;
  final bool byCategory;
  final bool showCount;

  /// Attached to the rendered header so [LibrarySectionsView]'s scroll
  /// listener can read its on-screen position.
  final GlobalKey headerKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = byCategory
        ? ref.watch(
            categoryMangaListWithQueryAndFilterProvider(categoryId: section.id),
          )
        : ref.watch(
            groupedMangaListWithQueryAndFilterProvider(tabId: section.id),
          );
    final items = listAsync.value ?? const [];

    // A lone header over no rows just looks broken.
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _SectionHeaderDelegate(
            headerKey: headerKey,
            title: showCount
                ? '${section.name} (${items.length})'
                : section.name,
            // Opaque, so rows scrolling under a pinned header stay hidden.
            background: context.theme.colorScheme.surface,
            foreground: context.theme.colorScheme.primary,
          ),
        ),
        LibraryMangaSliver(
          items: items,
          onOpen: (manga) => MangaRoute(
            mangaId: manga.id,
            categoryId: byCategory ? section.id : null,
          ).push(context),
        ),
      ],
    );
  }
}

class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SectionHeaderDelegate({
    required this.headerKey,
    required this.title,
    required this.background,
    required this.foreground,
  });

  final GlobalKey headerKey;
  final String title;
  final Color background;
  final Color foreground;

  static const _height = 40.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      key: headerKey,
      height: _height,
      color: background,
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        title,
        overflow: TextOverflow.ellipsis,
        style: context.theme.textTheme.titleSmall?.copyWith(color: foreground),
      ),
    );
  }

  @override
  bool shouldRebuild(_SectionHeaderDelegate old) =>
      old.title != title ||
      old.background != background ||
      old.foreground != foreground;
}
