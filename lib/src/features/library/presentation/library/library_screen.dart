// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../constants/enum.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../../widgets/manga_cover/list/manga_cover_descriptive_list_tile.dart';
import '../../../../widgets/manga_cover/list/manga_cover_list_tile.dart';
import '../../../../widgets/search_field.dart';
import '../../../../widgets/shell/update_banner_state.dart';
import '../../../manga_book/data/updates/updates_repository.dart';
import '../../../manga_book/widgets/update_status_popup_menu.dart';
import '../../../offline/presentation/offline_server_mismatch_banner.dart';
import '../../../settings/presentation/appearance/widgets/grid_cover_width_slider/grid_cover_width_slider.dart';
import '../../domain/category/category_model.dart';
import '../../domain/library_group.dart';
import '../category/controller/edit_category_controller.dart';
import 'category_manga_list.dart';
import 'controller/library_controller.dart';
import 'controller/library_grouping.dart';
import 'controller/library_manga_list.dart';
import 'widgets/library_manga_organizer.dart';

/// Wraps a library Scaffold body so the offline server-mismatch banner sits
/// below the app bar (inside the Scaffold), not floating over the status bar.
Widget _libraryBody(Widget body) => Column(
      children: [
        const OfflineServerMismatchBanner(),
        Expanded(child: body),
      ],
    );

class LibraryScreen extends HookConsumerWidget {
  const LibraryScreen({super.key, required this.categoryId});
  final int categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupType =
        ref.watch(libraryGroupTypeProvider) ?? kDefaultLibraryGroupType;

    // Standing rule: whenever ANY library update finishes (pull-triggered,
    // menu-triggered, or server-scheduled), re-read the library so the new
    // chapters it found appear without a manual refresh. Tracks the last
    // known running state and fires on the running→idle edge, ignoring the
    // transient null frames a socket reconnect emits.
    final lastRunning = useRef<bool>(false);
    ref.listen(updateRunningSocketProvider, (_, next) {
      final running = next.valueOrNull;
      if (running == null) return;
      if (lastRunning.value && !running) {
        ref.invalidate(libraryMangaListProvider);
      }
      lastRunning.value = running;
    });

    return groupType == LibraryGroup.byDefault
        ? _DefaultLibraryScreen(categoryId: categoryId)
        : _GroupedLibraryScreen(groupType: groupType);
  }
}

// ─────────────────── BY_DEFAULT (unchanged behaviour) ───────────────────────

class _DefaultLibraryScreen extends HookConsumerWidget {
  const _DefaultLibraryScreen({required this.categoryId});
  final int categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(toastProvider);
    final categoryList = ref.watch(visibleCategoryListProvider);
    final searchToggled = useState(false);
    // Show the search bar when the user opens it OR when a query was set
    // programmatically (tapping a tag → Search opens the library on that tag).
    final showSearch =
        searchToggled.value || ref.watch(libraryQueryProvider).isNotBlank;
    useEffect(() {
      categoryList.showToastOnError(toast, withMicrotask: true);
      return;
    }, [categoryList.valueOrNull]);

    return categoryList.showUiWhenData(
      context,
      (data) {
        if (data.isBlank) {
          return Emoticons(
            title: context.l10n.noCategoriesFound,
            button: TextButton(
              onPressed: () => ref.refresh(categoryControllerProvider.future),
              child: Text(context.l10n.refresh),
            ),
          );
        } else {
          return DefaultTabController(
            length: data!.length,
            // The route param is a category ID (e.g. from quick-search), not a
            // positional tab index — the visible list filters out empty/hidden
            // categories, so id != index. Select the tab whose category matches
            // the id, falling back to the first tab if it isn't visible (#284).
            initialIndex: max(0, data.indexWhere((c) => c.id == categoryId)),
            child: Scaffold(
              appBar: AppBar(
                title: !showSearch
                    ? Text(context.l10n.library)
                    : SearchField(
                        initialText: ref.read(libraryQueryProvider),
                        highlightDsl: true,
                        // Only grab focus when the user opened search; a tag-set
                        // query shows results without popping the keyboard.
                        autofocus: searchToggled.value,
                        onChanged: (val) =>
                            ref.read(libraryQueryProvider.notifier).update(val),
                        onClose: () => searchToggled.value = false,
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.help_outline_rounded),
                            tooltip: context.l10n.searchTips,
                            onPressed: () => showSearchTips(context),
                          ),
                          Consumer(
                            builder: (context, ref, child) => IconButton(
                              icon: Icon(Icons.travel_explore_rounded),
                              tooltip: context.l10n.globalSearch,
                              onPressed: ref
                                      .watch(libraryQueryProvider)
                                      .isNotBlank
                                  ? () => GlobalSearchRoute(
                                        query: ref.read(libraryQueryProvider),
                                      ).go(context)
                                  : null,
                            ),
                          )
                        ],
                      ),
                bottom: data.length.isGreaterThan(1) &&
                        ref.watch(categoryTabsProvider).ifNull(true)
                    ? TabBar(
                        isScrollable: true,
                        tabs:
                            data.map((e) => _CategoryTab(category: e)).toList(),
                        dividerColor: Colors.transparent,
                      )
                    : null,
                actions: showSearch
                    ? [SizedBox.shrink()]
                    : [
                        IconButton(
                          onPressed: () => searchToggled.value = true,
                          icon: const Icon(Icons.search_rounded),
                        ),
                        Builder(
                          builder: (context) => IconButton(
                            onPressed: () {
                              if (context.isTablet) {
                                Scaffold.of(context).openEndDrawer();
                              } else {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: KBorderRadius.rT16.radius,
                                  ),
                                  clipBehavior: Clip.hardEdge,
                                  // The organizer sizes itself to the active
                                  // tab's content (capped at 72% height), so no
                                  // fixed-height wrapper.
                                  builder: (_) => const LibraryMangaOrganizer(),
                                );
                              }
                            },
                            icon: const Icon(Icons.filter_list_rounded),
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            return UpdateStatusPopupMenu(
                              getCategory: () => data.isNotBlank
                                  ? data[DefaultTabController.of(context).index]
                                  : null,
                            );
                          },
                        ),
                      ],
              ),
              endDrawerEnableOpenDragGesture: false,
              endDrawer: const Drawer(
                width: kDrawerWidth,
                shape: RoundedRectangleBorder(),
                child: LibraryMangaOrganizer(),
              ),
              body: _libraryBody(
                data.isBlank
                    ? Emoticons(
                        title: context.l10n.noCategoriesFound,
                        button: TextButton(
                          onPressed: () =>
                              ref.refresh(categoryControllerProvider.future),
                          child: Text(context.l10n.refresh),
                        ),
                      )
                    : Padding(
                        padding: KEdgeInsets.h8.size,
                        child: TabBarView(
                          children: data
                              .map((e) => CategoryMangaList(
                                    categoryId:
                                        e.id.getValueOnNullOrNegative(),
                                  ))
                              .toList(),
                        ),
                      ),
              ),
            ),
          );
        }
      },
      refresh: () => ref.refresh(categoryControllerProvider.future),
      wrapper: (body) => Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.library),
        ),
        body: _libraryBody(body),
      ),
    );
  }
}

// ─────────────────── non-default group modes ────────────────────────────────

class _GroupedLibraryScreen extends HookConsumerWidget {
  const _GroupedLibraryScreen({required this.groupType});
  final int groupType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(toastProvider);
    final groupedTabsAsync = ref.watch(libraryGroupedTabsProvider);
    final searchToggled = useState(false);
    // Show the search bar when the user opens it OR when a query was set
    // programmatically (tapping a tag → Search opens the library on that tag).
    final showSearch =
        searchToggled.value || ref.watch(libraryQueryProvider).isNotBlank;
    useEffect(() {
      groupedTabsAsync.showToastOnError(toast, withMicrotask: true);
      return;
    }, [groupedTabsAsync.valueOrNull]);

    return groupedTabsAsync.showUiWhenData(
      context,
      (tabs) {
        if (tabs.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text(context.l10n.library)),
            body: Emoticons(
              title: context.l10n.noCategoriesFound,
              button: TextButton(
                onPressed: () => ref.refresh(libraryGroupedTabsProvider.future),
                child: Text(context.l10n.refresh),
              ),
            ),
          );
        }
        return DefaultTabController(
          // Key on the tab set so the controller fully rebuilds (resetting the
          // selected index to 0) when the group mode changes the tab count.
          // Without this, switching e.g. By Source (many tabs) → By Status
          // (fewer) leaves the controller's index out of range and it churns
          // into an infinite rebuild flicker.
          key: ValueKey('group-$groupType-${tabs.length}'),
          length: tabs.length,
          child: Scaffold(
            appBar: AppBar(
              title: !showSearch
                  ? Text(context.l10n.library)
                  : SearchField(
                      initialText: ref.read(libraryQueryProvider),
                      highlightDsl: true,
                      autofocus: searchToggled.value,
                      onChanged: (val) =>
                          ref.read(libraryQueryProvider.notifier).update(val),
                      onClose: () => searchToggled.value = false,
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.help_outline_rounded),
                          tooltip: context.l10n.searchTips,
                          onPressed: () => showSearchTips(context),
                        ),
                      ],
                    ),
              bottom: tabs.length > 1
                  ? TabBar(
                      isScrollable: true,
                      tabs: tabs.map((t) => Tab(text: t.name)).toList(),
                      dividerColor: Colors.transparent,
                    )
                  : null,
              actions: showSearch
                  ? [SizedBox.shrink()]
                  : [
                      IconButton(
                        onPressed: () => searchToggled.value = true,
                        icon: const Icon(Icons.search_rounded),
                      ),
                      Builder(
                        builder: (context) => IconButton(
                          onPressed: () {
                            if (context.isTablet) {
                              Scaffold.of(context).openEndDrawer();
                            } else {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: RoundedRectangleBorder(
                                  borderRadius: KBorderRadius.rT16.radius,
                                ),
                                clipBehavior: Clip.hardEdge,
                                builder: (_) => const LibraryMangaOrganizer(),
                              );
                            }
                          },
                          icon: const Icon(Icons.filter_list_rounded),
                        ),
                      ),
                    ],
            ),
            endDrawerEnableOpenDragGesture: false,
            endDrawer: const Drawer(
              width: kDrawerWidth,
              shape: RoundedRectangleBorder(),
              child: LibraryMangaOrganizer(),
            ),
            body: _libraryBody(
              Padding(
                padding: KEdgeInsets.h8.size,
                child: TabBarView(
                  children:
                      tabs.map((t) => _GroupedMangaList(tabId: t.id)).toList(),
                ),
              ),
            ),
          ),
        );
      },
      refresh: () => ref.refresh(libraryGroupedTabsProvider.future),
      wrapper: (body) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.library)),
        body: _libraryBody(body),
      ),
    );
  }
}

// ─────────────────── widgets ────────────────────────────────────────────────

/// A Tab widget for a single library category.
///
/// When [categoryNumberOfItemsProvider] is on, it watches the per-category
/// filtered manga list (the SAME provider that [CategoryMangaList] uses) and
/// appends "(N)" to the label so the count reflects the currently active query
/// and filter state — including offline mode where server totalCount is stale.
class _CategoryTab extends ConsumerWidget {
  const _CategoryTab({required this.category});
  final CategoryDto category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showCount = ref.watch(categoryNumberOfItemsProvider).ifNull(false);
    if (!showCount) {
      return Tab(text: category.name);
    }
    final mangaListAsync = ref.watch(
      categoryMangaListWithQueryAndFilterProvider(
        categoryId: category.id,
      ),
    );
    final count = mangaListAsync.valueOrNull?.length;
    final label = count != null ? '${category.name} ($count)' : category.name;
    return Tab(text: label);
  }
}

/// A manga grid/list for a non-default group tab (BY_SOURCE, BY_STATUS,
/// UNGROUPED), fed from [groupedMangaListWithQueryAndFilterProvider].
class _GroupedMangaList extends ConsumerWidget {
  const _GroupedMangaList({required this.tabId});
  final int tabId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mangaListAsync = ref.watch(
      groupedMangaListWithQueryAndFilterProvider(tabId: tabId),
    );
    final displayMode = ref.watch(libraryDisplayModeProvider);
    final gridWidth = ref.watch(gridMinWidthProvider);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final portraitCols = ref.watch(libraryPortraitColumnsProvider) ?? 0;
    final landscapeCols = ref.watch(libraryLandscapeColumnsProvider) ?? 0;
    final fixedCols = isLandscape ? landscapeCols : portraitCols;

    SliverGridDelegate gridDelegate({bool titleBelow = false}) => fixedCols > 0
        ? SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: fixedCols,
            crossAxisSpacing: 2.0,
            mainAxisSpacing: 2.0,
            childAspectRatio: titleBelow ? 0.62 : 0.75,
          )
        : mangaCoverGridDelegate(gridWidth, titleBelow: titleBelow);

    return mangaListAsync.showUiWhenData(
      context,
      (data) {
        if (data == null || data.isEmpty) {
          return Emoticons(title: context.l10n.noCategoryMangaFound);
        }
        final items = data;
        return RefreshIndicator(
          // Grouped views (by source/status/ungrouped) have no single category
          // to update, so pull triggers a whole-library source-check (matches
          // Komikku's non-BY_DEFAULT rule). The banner shows its progress; the
          // spinner only waits on the immediate server re-read.
          onRefresh: () async {
            ref.read(updateOptimisticProvider.notifier).arm();
            unawaited(ref
                .read(updatesRepositoryProvider)
                .fetchUpdates()
                .catchError((Object _) {}));
            ref.invalidate(libraryMangaListProvider);
            await ref.read(libraryMangaListProvider.future);
          },
          child: switch (displayMode) {
            DisplayMode.list || null => ListView.builder(
                itemExtent: 96,
                itemCount: items.length,
                itemBuilder: (context, index) => MangaCoverListTile(
                  manga: items[index],
                  selected: false,
                  onPressed: () =>
                      MangaRoute(mangaId: items[index].id).push(context),
                  onLongPress: () {},
                  showCountBadges: true,
                ),
              ),
            DisplayMode.grid => GridView.builder(
                gridDelegate: gridDelegate(),
                itemCount: items.length,
                itemBuilder: (context, index) => MangaCoverGridTile(
                  manga: items[index],
                  selected: false,
                  onLongPress: () {},
                  onPressed: () =>
                      MangaRoute(mangaId: items[index].id).push(context),
                  showCountBadges: true,
                  showDarkOverlay: false,
                ),
              ),
            DisplayMode.comfortableGrid => GridView.builder(
                gridDelegate: gridDelegate(titleBelow: true),
                itemCount: items.length,
                itemBuilder: (context, index) => MangaCoverGridTile(
                  manga: items[index],
                  selected: false,
                  onLongPress: () {},
                  onPressed: () =>
                      MangaRoute(mangaId: items[index].id).push(context),
                  showCountBadges: true,
                  titleBelow: true,
                  showDarkOverlay: false,
                ),
              ),
            DisplayMode.descriptiveList => ListView.builder(
                itemExtent: 176,
                itemCount: items.length,
                itemBuilder: (context, index) => MangaCoverDescriptiveListTile(
                  manga: items[index],
                  selected: false,
                  onPressed: () =>
                      MangaRoute(mangaId: items[index].id).push(context),
                  onLongPress: () {},
                  showBadges: true,
                ),
              ),
            DisplayMode.coverOnly => GridView.builder(
                gridDelegate: gridDelegate(),
                itemCount: items.length,
                itemBuilder: (context, index) => MangaCoverGridTile(
                  manga: items[index],
                  selected: false,
                  onLongPress: () {},
                  onPressed: () =>
                      MangaRoute(mangaId: items[index].id).push(context),
                  showCountBadges: true,
                  showTitle: false,
                  showDarkOverlay: false,
                ),
              ),
          },
        );
      },
      refresh: () => ref.refresh(libraryMangaListProvider),
    );
  }
}

/// Shows the library search DSL cheat-sheet (opened from the search bar's help
/// icon), so the query syntax is discoverable rather than hidden.
void showSearchTips(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.searchTips),
      content: Text(context.l10n.searchTipsBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.close),
        ),
      ],
    ),
  );
}
