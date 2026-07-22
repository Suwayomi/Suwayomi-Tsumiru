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
import '../../../offline/presentation/server_unreachable_banner.dart';
import '../../../settings/presentation/appearance/widgets/grid_cover_width_slider/grid_cover_width_slider.dart';
import '../../../settings/presentation/library/widgets/persistent_search_bar/persistent_search_bar.dart';
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
    const ServerUnreachableBanner(),
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
      final running = next.value;
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

// ─────────────────── shared pieces ───────────────────────────────────────────

/// Filter/sort/display organizer button: end-drawer on tablets, bottom sheet
/// on phones.
Widget _organizerButton() => Builder(
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
          // The organizer sizes itself to the active tab's content
          // (capped at 72% height), so no fixed-height wrapper.
          builder: (_) => const LibraryMangaOrganizer(),
        );
      }
    },
    icon: const Icon(Icons.filter_list_rounded),
  ),
);

/// Whether the inline search bar (located via [searchBarKey]) has scrolled out
/// of the viewport, meaning the pinned app bar should host the search field
/// instead.
///
/// Evaluated defensively:
///  - a missing or zero-height bar (the library is still loading, so
///    [_LibrarySearchBar] collapsed) is never "hidden" — reporting hidden then
///    leaves the app-bar field up while the inline bar reappears at offset 0,
///    showing both bars at once (the pull-to-refresh glitch);
///  - re-evaluated after every build, not only on scroll events, because a
///    refresh can change the header extent (clamping the offset) without
///    emitting any further scroll notification.
bool _useIsSearchBarHidden(
  ScrollController controller,
  GlobalKey searchBarKey,
) {
  final context = useContext();
  final isHidden = useState(false);
  final evaluate = useCallback(() {
    final box = searchBarKey.currentContext?.findRenderObject() as RenderBox?;
    final height = (box != null && box.hasSize) ? box.size.height : 0.0;
    final offset = controller.hasClients ? controller.offset : 0.0;
    isHidden.value = height > 0 && offset >= height - 4;
  }, [controller, searchBarKey]);
  useEffect(() {
    controller.addListener(evaluate);
    return () => controller.removeListener(evaluate);
  }, [controller, evaluate]);
  useEffect(() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) evaluate();
    });
    return null;
  });
  return isHidden.value;
}

// ─────────────────── BY_DEFAULT (unchanged behaviour) ───────────────────────

class _DefaultLibraryScreen extends ConsumerWidget {
  const _DefaultLibraryScreen({required this.categoryId});
  final int categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(libraryPersistentSearchBarProvider).ifNull()
      ? _DefaultLibraryStickySearch(categoryId: categoryId)
      : _DefaultLibraryToggledSearch(categoryId: categoryId);
}

/// Default layout (setting off): the search field lives behind the app-bar
/// search button, Mihon/Komikku style.
class _DefaultLibraryToggledSearch extends HookConsumerWidget {
  const _DefaultLibraryToggledSearch({required this.categoryId});
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
    }, [categoryList.value]);

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
                    // SearchField no longer pads itself; keep the pre-refactor
                    // inset and large-tablet width cap here.
                    : SizedBox(
                        width: context.isLargeTablet
                            ? context.widthScale(scale: .5)
                            : null,
                        child: Padding(
                          padding: KEdgeInsets.h16v4.size,
                          child: SearchField(
                            initialText: ref.read(libraryQueryProvider),
                            highlightDsl: true,
                            // Only grab focus when the user opened search; a
                            // tag-set query shows results without popping the
                            // keyboard.
                            autofocus: searchToggled.value,
                            onChanged: (val) => ref
                                .read(libraryQueryProvider.notifier)
                                .update(val),
                            onClose: () => searchToggled.value = false,
                            actions: [
                              IconButton(
                                icon: const Icon(Icons.help_outline_rounded),
                                tooltip: context.l10n.searchTips,
                                onPressed: () => showSearchTips(context),
                              ),
                              Consumer(
                                builder: (context, ref, child) => IconButton(
                                  icon: const Icon(
                                    Icons.travel_explore_rounded,
                                  ),
                                  tooltip: context.l10n.globalSearch,
                                  onPressed:
                                      ref.watch(libraryQueryProvider).isNotBlank
                                      ? () => GlobalSearchRoute(
                                          query: ref.read(libraryQueryProvider),
                                        ).go(context)
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                bottom:
                    data.length.isGreaterThan(1) &&
                        ref.watch(categoryTabsProvider).ifNull(true)
                    ? TabBar(
                        isScrollable: true,
                        tabs: data
                            .map((e) => _CategoryTab(category: e))
                            .toList(),
                        dividerColor: Colors.transparent,
                      )
                    : null,
                actions: showSearch
                    ? const [SizedBox.shrink()]
                    : [
                        IconButton(
                          onPressed: () => searchToggled.value = true,
                          icon: const Icon(Icons.search_rounded),
                        ),
                        _organizerButton(),
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
                Padding(
                  padding: KEdgeInsets.h8.size,
                  child: TabBarView(
                    children: data
                        .map(
                          (e) => CategoryMangaList(
                            key: ValueKey(e.id.getValueOnNullOrNegative()),
                            categoryId: e.id.getValueOnNullOrNegative(),
                          ),
                        )
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
        appBar: AppBar(title: Text(context.l10n.library)),
        body: _libraryBody(body),
      ),
    );
  }
}

/// Opt-in layout (More → Settings → Library): the search bar is always visible
/// under the app bar and sticks into it when scrolled away, Yokai/J2K style.
class _DefaultLibraryStickySearch extends HookConsumerWidget {
  const _DefaultLibraryStickySearch({required this.categoryId});
  final int categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(toastProvider);
    final categoryList = ref.watch(visibleCategoryListProvider);
    final scrollController = useScrollController();
    final searchBarKey = useMemoized(() => GlobalKey());
    final isSearchBarHidden = _useIsSearchBarHidden(
      scrollController,
      searchBarKey,
    );

    useEffect(() {
      categoryList.showToastOnError(toast, withMicrotask: true);
      return;
    }, [categoryList.value]);

    return categoryList.showUiWhenData(
      context,
      (data) {
        if (data.isBlank) {
          return Scaffold(
            appBar: AppBar(title: Text(context.l10n.library)),
            body: Emoticons(
              title: context.l10n.noCategoriesFound,
              button: TextButton(
                onPressed: () => ref.refresh(categoryControllerProvider.future),
                child: Text(context.l10n.refresh),
              ),
            ),
          );
        }

        final showTabs =
            data!.length > 1 && ref.watch(categoryTabsProvider).ifNull(true);

        return DefaultTabController(
          length: data.length,
          // The route param is a category ID (e.g. from quick-search), not a
          // positional tab index — the visible list filters out empty/hidden
          // categories, so id != index. Select the tab whose category matches
          // the id, falling back to the first tab if it isn't visible (#284).
          initialIndex: max(0, data.indexWhere((c) => c.id == categoryId)),
          child: Scaffold(
            endDrawerEnableOpenDragGesture: false,
            endDrawer: const Drawer(
              width: kDrawerWidth,
              shape: RoundedRectangleBorder(),
              child: LibraryMangaOrganizer(),
            ),
            body: NestedScrollView(
              controller: scrollController,
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverAppBar(
                    pinned: true,
                    floating: false,
                    title: isSearchBarHidden
                        ? const _LibrarySearchBar(inAppBar: true)
                        : Text(context.l10n.library),
                    actions: [
                      _organizerButton(),
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
                  SliverToBoxAdapter(
                    child: KeyedSubtree(
                      key: searchBarKey,
                      child: const _LibrarySearchBar(inAppBar: false),
                    ),
                  ),
                  if (showTabs)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _SliverTabBarDelegate(
                        TabBar(
                          isScrollable: true,
                          tabs: data
                              .map((e) => _CategoryTab(category: e))
                              .toList(),
                          dividerColor: Colors.transparent,
                        ),
                      ),
                    ),
                ];
              },
              // This Scaffold has no appBar (the header slivers replace it), so
              // its body still carries the status-bar padding and the grids
              // inside would re-apply it as list padding — a dead gap between
              // the tab bar and the first row. The header slivers consume that
              // inset; drop it for the body. The Builder matters: removePadding
              // must start from the MediaQuery inside the Scaffold body slot.
              body: Builder(
                builder: (context) => MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: _libraryBody(
                    Padding(
                      padding: KEdgeInsets.h8.size,
                      child: TabBarView(
                        children: data
                            .map(
                              (e) => CategoryMangaList(
                                key: ValueKey(e.id.getValueOnNullOrNegative()),
                                categoryId: e.id.getValueOnNullOrNegative(),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      refresh: () => ref.refresh(categoryControllerProvider.future),
      wrapper: (body) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.library)),
        body: _libraryBody(body),
      ),
    );
  }
}

// ─────────────────── non-default group modes ────────────────────────────────

class _GroupedLibraryScreen extends ConsumerWidget {
  const _GroupedLibraryScreen({required this.groupType});
  final int groupType;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(libraryPersistentSearchBarProvider).ifNull()
      ? _GroupedLibraryStickySearch(groupType: groupType)
      : _GroupedLibraryToggledSearch(groupType: groupType);
}

/// Default layout (setting off): search behind the app-bar toggle.
class _GroupedLibraryToggledSearch extends HookConsumerWidget {
  const _GroupedLibraryToggledSearch({required this.groupType});
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
    }, [groupedTabsAsync.value]);

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
                  // SearchField no longer pads itself; keep the pre-refactor
                  // inset and large-tablet width cap here.
                  : SizedBox(
                      width: context.isLargeTablet
                          ? context.widthScale(scale: .5)
                          : null,
                      child: Padding(
                        padding: KEdgeInsets.h16v4.size,
                        child: SearchField(
                          initialText: ref.read(libraryQueryProvider),
                          highlightDsl: true,
                          autofocus: searchToggled.value,
                          onChanged: (val) => ref
                              .read(libraryQueryProvider.notifier)
                              .update(val),
                          onClose: () => searchToggled.value = false,
                          actions: [
                            IconButton(
                              icon: const Icon(Icons.help_outline_rounded),
                              tooltip: context.l10n.searchTips,
                              onPressed: () => showSearchTips(context),
                            ),
                          ],
                        ),
                      ),
                    ),
              bottom: tabs.length > 1
                  ? TabBar(
                      isScrollable: true,
                      tabs: tabs.map((t) => Tab(text: t.name)).toList(),
                      dividerColor: Colors.transparent,
                    )
                  : null,
              actions: showSearch
                  ? const [SizedBox.shrink()]
                  : [
                      IconButton(
                        onPressed: () => searchToggled.value = true,
                        icon: const Icon(Icons.search_rounded),
                      ),
                      IconButton(
                        tooltip: context.l10n.migrationPickSourceTitle,
                        onPressed: () =>
                            const MigrationSourcePickerRoute().push(context),
                        icon: const Icon(Icons.swap_horiz_rounded),
                      ),
                      _organizerButton(),
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
                  children: tabs
                      .map(
                        (t) =>
                            _GroupedMangaList(key: ValueKey(t.id), tabId: t.id),
                      )
                      .toList(),
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

/// Opt-in layout: always-visible search bar that sticks into the app bar.
class _GroupedLibraryStickySearch extends HookConsumerWidget {
  const _GroupedLibraryStickySearch({required this.groupType});
  final int groupType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(toastProvider);
    final groupedTabsAsync = ref.watch(libraryGroupedTabsProvider);
    final scrollController = useScrollController();
    final searchBarKey = useMemoized(() => GlobalKey());
    final isSearchBarHidden = _useIsSearchBarHidden(
      scrollController,
      searchBarKey,
    );

    useEffect(() {
      groupedTabsAsync.showToastOnError(toast, withMicrotask: true);
      return;
    }, [groupedTabsAsync.value]);

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
            endDrawerEnableOpenDragGesture: false,
            endDrawer: const Drawer(
              width: kDrawerWidth,
              shape: RoundedRectangleBorder(),
              child: LibraryMangaOrganizer(),
            ),
            body: NestedScrollView(
              controller: scrollController,
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverAppBar(
                    pinned: true,
                    floating: false,
                    title: isSearchBarHidden
                        ? const _LibrarySearchBar(inAppBar: true)
                        : Text(context.l10n.library),
                    actions: [_organizerButton()],
                  ),
                  SliverToBoxAdapter(
                    child: KeyedSubtree(
                      key: searchBarKey,
                      child: const _LibrarySearchBar(inAppBar: false),
                    ),
                  ),
                  if (tabs.length > 1)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _SliverTabBarDelegate(
                        TabBar(
                          isScrollable: true,
                          tabs: tabs.map((t) => Tab(text: t.name)).toList(),
                          dividerColor: Colors.transparent,
                        ),
                      ),
                    ),
                ];
              },
              // See _DefaultLibraryStickySearch: drop the status-bar padding
              // the header slivers already consumed, from inside the body slot.
              body: Builder(
                builder: (context) => MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: _libraryBody(
                    Padding(
                      padding: KEdgeInsets.h8.size,
                      child: TabBarView(
                        children: tabs
                            .map(
                              (t) => _GroupedMangaList(
                                key: ValueKey(t.id),
                                tabId: t.id,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
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
      categoryMangaListWithQueryAndFilterProvider(categoryId: category.id),
    );
    final count = mangaListAsync.value?.length;
    final label = count != null ? '${category.name} ($count)' : category.name;
    return Tab(text: label);
  }
}

/// A manga grid/list for a non-default group tab (BY_SOURCE, BY_STATUS,
/// UNGROUPED), fed from [groupedMangaListWithQueryAndFilterProvider].
class _GroupedMangaList extends ConsumerWidget {
  const _GroupedMangaList({super.key, required this.tabId});
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

    return mangaListAsync.showUiWhenData(context, (data) {
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
          unawaited(
            ref
                .read(updatesRepositoryProvider)
                .fetchUpdates()
                .catchError((Object _) {}),
          );
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
    }, refresh: () => ref.refresh(libraryMangaListProvider));
  }
}

/// Shows the library search DSL cheat-sheet (opened from the search bar's help
/// icon), so the query syntax is discoverable rather than hidden.
void showSearchTips(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.searchTips),
      // The `{a|b}` OR-group example lives here rather than in the l10n string
      // because ICU message syntax reserves curly braces for placeholders.
      content: Text(
        '${context.l10n.searchTipsBody}'
        '\nMatch any of these: {genre:action|genre:romance}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.close),
        ),
      ],
    ),
  );
}

/// The persistent-mode search field. Rendered in two hosts: inline under the
/// app bar ([inAppBar] false, with its own inset) and as the pinned app bar's
/// title once the inline instance scrolls away ([inAppBar] true).
class _LibrarySearchBar extends ConsumerWidget {
  const _LibrarySearchBar({required this.inAppBar});
  final bool inAppBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mangaListLoaded = ref.watch(libraryMangaListProvider).value != null;
    if (!mangaListLoaded) return const SizedBox.shrink();

    final query = ref.watch(libraryQueryProvider) ?? '';
    final field = SearchField(
      initialText: query,
      hintText: context.l10n.searchLibraryHint,
      onChanged: (val) => ref.read(libraryQueryProvider.notifier).update(val),
      onClose: () => ref.read(libraryQueryProvider.notifier).update(''),
      autofocus: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.help_outline_rounded),
          tooltip: context.l10n.searchTips,
          onPressed: () => showSearchTips(context),
        ),
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.travel_explore_rounded),
            tooltip: context.l10n.globalSearch,
            onPressed: () => GlobalSearchRoute(query: query).go(context),
          ),
      ],
      highlightDsl: true,
      hintBehavior: SearchFieldHintBehavior.forceHint,
    );

    return inAppBar
        ? field
        : Padding(
            padding: const EdgeInsets.fromLTRB(11, 0, 11, 4),
            child: field,
          );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabBarDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: tabBar,
    );
  }

  // The header builder recreates the TabBar whenever the screen rebuilds, so
  // comparing instances keeps the pinned row current — returning false froze
  // the first TabBar forever, so renamed/added categories never showed up.
  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar;
}
