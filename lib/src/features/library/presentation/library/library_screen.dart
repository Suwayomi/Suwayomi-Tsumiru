// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../constants/enum.dart';
import '../../../../routes/navigation.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/search_field.dart';
import '../../../../widgets/shell/update_banner_state.dart';
import '../../../manga_book/data/updates/updates_repository.dart';
import '../../../manga_book/widgets/update_status_popup_menu.dart';
import '../../../offline/data/server_reachability.dart';
import '../../../offline/presentation/offline_server_mismatch_banner.dart';
import '../../../offline/presentation/offline_view_loading.dart';
import '../../../offline/presentation/server_unreachable_banner.dart';
import '../../../settings/presentation/library/widgets/persistent_search_bar/persistent_search_bar.dart';
import '../../domain/category/category_model.dart';
import '../../domain/library_group.dart';
import '../category/controller/edit_category_controller.dart';
import 'category_manga_list.dart';
import 'controller/library_controller.dart';
import 'controller/library_grouping.dart';
import 'controller/library_manga_list.dart';
import 'widgets/library_manga_grid_view.dart';
import 'widgets/library_manga_organizer.dart';
import 'widgets/library_sections_view.dart';

/// Wraps a library Scaffold body so the offline server-mismatch banner sits
/// below the app bar (inside the Scaffold), not floating over the status bar.
/// [grouped] picks what the banner's Retry re-asks for: the two library screens
/// draw their tabs from different providers, and refreshing the other one left
/// the content stale while the banner vanished.
Widget _libraryBody(WidgetRef ref, Widget body, {bool grouped = false}) =>
    Column(
      children: [
        ServerUnreachableBanner(
          onRetry: () => ref.invalidate(
            grouped ? libraryGroupedTabsProvider : categoryControllerProvider,
          ),
        ),
        const OfflineServerMismatchBanner(),
        Expanded(child: body),
      ],
    );

/// Categories as headers-style sections. Id 0 is Default/uncategorised.
List<LibrarySection> _categorySections(List<CategoryDto> categories) => [
  for (final c in categories)
    (id: c.id.getValueOnNullOrNegative(), name: c.name),
];

/// Grouped tabs as headers-style sections.
List<LibrarySection> _groupSections(List<GroupedTab> tabs) => [
  for (final t in tabs) (id: t.id, name: t.name),
];

/// Picks [TabBarView] vs [LibrarySectionsView]. Only continuous Section-Headers
/// gets the sections view; every other combination is paginated.
bool _useTabs(LibraryGroupStyle style, bool showAllCategories) =>
    style == LibraryGroupStyle.tabs || !showAllCategories;

/// The floating tab strip is Tabs-mode's own affordance; Section-Headers mode
/// carries section identity in its headers instead.
bool _showTabBar(LibraryGroupStyle style, bool categoryTabsOn) =>
    style == LibraryGroupStyle.tabs && categoryTabsOn;

/// Paginated Section-Headers has no floating strip, so each page grows its own
/// non-sticky header.
bool _showInlineHeaders(LibraryGroupStyle style, bool showAllCategories) =>
    style == LibraryGroupStyle.headers && !showAllCategories;

/// The library body for the active group style: a page per group behind the tab
/// strip, or one continuous scroll with a sticky header per group.
Widget _groupedBody({
  required bool useTabs,
  required List<LibrarySection> sections,
  required bool byCategory,
  required bool showCounts,
  required List<Widget> Function() tabViews,
}) => Padding(
  padding: KEdgeInsets.h8.size,
  child: useTabs
      ? Builder(
          // Every tab's CustomScrollView shares the ambient
          // PrimaryScrollController, so desktop's auto-Scrollbar throws
          // "attached to more than one ScrollPosition" once two tabs are alive.
          // Dropping the scrollbar removes the reader; scrolling is untouched.
          builder: (context) => ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: TabBarView(children: tabViews()),
          ),
        )
      : LibrarySectionsView(
          sections: sections,
          byCategory: byCategory,
          showCounts: showCounts,
        ),
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
    final style =
        ref.watch(libraryGroupStyleKeyProvider) ?? LibraryGroupStyle.tabs;
    final categoryTabsOn = ref.watch(categoryTabsProvider).ifNull(true);
    final showAllCategories = ref
        .watch(sectionHeadersShowAllCategoriesProvider)
        .ifNull(false);
    final useTabs = _useTabs(style, showAllCategories);
    final showTabBar = _showTabBar(style, categoryTabsOn);
    final showInlineHeaders = _showInlineHeaders(style, showAllCategories);
    final showCounts = ref.watch(categoryNumberOfItemsProvider).ifNull(false);
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
      loadingWidget: const OfflineViewLoading(),
      offlineEscapeHatch: true,
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
            // Key on the category set so the controller fully rebuilds instead
            // of swapping its length in place — the same fix as the grouped
            // view below. A slow/reconnecting server fetch can replace a
            // cached category list with a differently-sized live one after the
            // tab bar is already showing; swapping the length while a drag is
            // active on the old controller left its disposed AnimationController
            // wired to a live gesture, crashing with a null-check in
            // _TabBarState._handleTabControllerAnimationTick.
            key: ValueKey('categories-${data!.map((c) => c.id).join(',')}'),
            length: data.length,
            // The route param is a category ID (e.g. from quick-search), not a
            // positional tab index — the visible list filters out empty/hidden
            // categories, so id != index. Select the tab whose category matches
            // the id, falling back to the first tab if it isn't visible (#284).
            initialIndex: max(0, data.indexWhere((c) => c.id == categoryId)),
            child: Scaffold(
              appBar: AppBar(
                title: !showSearch
                    ? _LibraryTitle(sections: _categorySections(data))
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
                                      ? () => openGlobalSearch(
                                          context,
                                          query: ref.read(libraryQueryProvider),
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                bottom: showTabBar && data.length.isGreaterThan(1)
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
                              // Section-headers style has no "current" tab, so
                              // the menu targets the whole library there.
                              getCategory: () => useTabs && data.isNotBlank
                                  ? data[DefaultTabController.of(context).index]
                                  : null,
                              showDuplicatesButton: true,
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
                ref,
                _groupedBody(
                  useTabs: useTabs,
                  sections: _categorySections(data),
                  byCategory: true,
                  showCounts: showCounts,
                  tabViews: () => data.map((e) {
                    final id = e.id.getValueOnNullOrNegative();
                    final content = CategoryMangaList(
                      key: ValueKey(id),
                      categoryId: id,
                    );
                    return showInlineHeaders
                        ? _PagedSection(
                            key: ValueKey(id),
                            section: (id: id, name: e.name),
                            byCategory: true,
                            showCount: showCounts,
                            child: content,
                          )
                        : content;
                  }).toList(),
                ),
              ),
            ),
          );
        }
      },
      refresh: () {
        // A manual retry means "try the server again" — drop the offline pin.
        ref.read(viewOfflineNowProvider.notifier).set(false);
        ref.read(serverUnreachableProvider.notifier).set(false);
        ref.invalidate(categoryControllerProvider);
      },
      wrapper: (body) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.library)),
        body: _libraryBody(ref, body),
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
      loadingWidget: const OfflineViewLoading(),
      offlineEscapeHatch: true,
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

        final style =
            ref.watch(libraryGroupStyleKeyProvider) ?? LibraryGroupStyle.tabs;
        final categoryTabsOn = ref.watch(categoryTabsProvider).ifNull(true);
        final showAllCategories = ref
            .watch(sectionHeadersShowAllCategoriesProvider)
            .ifNull(false);
        final useTabs = _useTabs(style, showAllCategories);
        final showInlineHeaders = _showInlineHeaders(style, showAllCategories);
        final showCounts = ref
            .watch(categoryNumberOfItemsProvider)
            .ifNull(false);
        final showTabs = data!.length > 1 && _showTabBar(style, categoryTabsOn);

        return DefaultTabController(
          // See the matching comment on the toggled-search variant above: keys
          // the controller to the category set so it fully rebuilds instead of
          // swapping its length under an in-flight drag.
          key: ValueKey('categories-${data.map((c) => c.id).join(',')}'),
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
                        : _LibraryTitle(sections: _categorySections(data)),
                    actions: [
                      _organizerButton(),
                      Builder(
                        builder: (context) {
                          return UpdateStatusPopupMenu(
                            // Section-headers style has no "current" tab, so
                            // the menu targets the whole library there.
                            getCategory: () => useTabs && data.isNotBlank
                                ? data[DefaultTabController.of(context).index]
                                : null,
                            showDuplicatesButton: true,
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
                    ref,
                    _groupedBody(
                      useTabs: useTabs,
                      sections: _categorySections(data),
                      byCategory: true,
                      showCounts: showCounts,
                      tabViews: () => data.map((e) {
                        final id = e.id.getValueOnNullOrNegative();
                        final content = CategoryMangaList(
                          key: ValueKey(id),
                          categoryId: id,
                        );
                        return showInlineHeaders
                            ? _PagedSection(
                                key: ValueKey(id),
                                section: (id: id, name: e.name),
                                byCategory: true,
                                showCount: showCounts,
                                child: content,
                              )
                            : content;
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      refresh: () {
        // A manual retry means "try the server again" — drop the offline pin.
        ref.read(viewOfflineNowProvider.notifier).set(false);
        ref.read(serverUnreachableProvider.notifier).set(false);
        ref.invalidate(categoryControllerProvider);
      },
      wrapper: (body) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.library)),
        body: _libraryBody(ref, body),
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
    final style =
        ref.watch(libraryGroupStyleKeyProvider) ?? LibraryGroupStyle.tabs;
    final categoryTabsOn = ref.watch(categoryTabsProvider).ifNull(true);
    final showAllCategories = ref
        .watch(sectionHeadersShowAllCategoriesProvider)
        .ifNull(false);
    final useTabs = _useTabs(style, showAllCategories);
    final showTabBar = _showTabBar(style, categoryTabsOn);
    final showInlineHeaders = _showInlineHeaders(style, showAllCategories);
    final showCounts = ref.watch(categoryNumberOfItemsProvider).ifNull(false);
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
      loadingWidget: const OfflineViewLoading(),
      offlineEscapeHatch: true,
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
                  ? _LibraryTitle(sections: _groupSections(tabs))
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
              bottom: showTabBar && tabs.length > 1
                  ? TabBar(
                      isScrollable: true,
                      tabs: tabs
                          .map((t) => _GroupTab(tab: t, showCount: showCounts))
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
              ref,
              grouped: true,
              _groupedBody(
                useTabs: useTabs,
                sections: _groupSections(tabs),
                byCategory: false,
                showCounts: showCounts,
                tabViews: () => tabs.map((t) {
                  final content = _GroupedMangaList(
                    key: ValueKey(t.id),
                    tabId: t.id,
                  );
                  return showInlineHeaders
                      ? _PagedSection(
                          key: ValueKey(t.id),
                          section: (id: t.id, name: t.name),
                          byCategory: false,
                          showCount: showCounts,
                          child: content,
                        )
                      : content;
                }).toList(),
              ),
            ),
          ),
        );
      },
      refresh: () {
        ref.read(viewOfflineNowProvider.notifier).set(false);
        ref.read(serverUnreachableProvider.notifier).set(false);
        ref.invalidate(libraryGroupedTabsProvider);
      },
      // Changing the grouping type reloads this provider; keep the current
      // tabs — and their Scaffold's endDrawer — up instead of flashing the
      // spinner Scaffold below.
      skipLoadingOnReload: true,
      wrapper: (body) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.library)),
        body: _libraryBody(ref, body, grouped: true),
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
    final style =
        ref.watch(libraryGroupStyleKeyProvider) ?? LibraryGroupStyle.tabs;
    final categoryTabsOn = ref.watch(categoryTabsProvider).ifNull(true);
    final showAllCategories = ref
        .watch(sectionHeadersShowAllCategoriesProvider)
        .ifNull(false);
    final useTabs = _useTabs(style, showAllCategories);
    final showTabBar = _showTabBar(style, categoryTabsOn);
    final showInlineHeaders = _showInlineHeaders(style, showAllCategories);
    final showCounts = ref.watch(categoryNumberOfItemsProvider).ifNull(false);

    useEffect(() {
      groupedTabsAsync.showToastOnError(toast, withMicrotask: true);
      return;
    }, [groupedTabsAsync.value]);

    return groupedTabsAsync.showUiWhenData(
      context,
      loadingWidget: const OfflineViewLoading(),
      offlineEscapeHatch: true,
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
                        : _LibraryTitle(sections: _groupSections(tabs)),
                    actions: [_organizerButton()],
                  ),
                  SliverToBoxAdapter(
                    child: KeyedSubtree(
                      key: searchBarKey,
                      child: const _LibrarySearchBar(inAppBar: false),
                    ),
                  ),
                  if (showTabBar && tabs.length > 1)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _SliverTabBarDelegate(
                        TabBar(
                          isScrollable: true,
                          tabs: tabs
                              .map(
                                (t) => _GroupTab(tab: t, showCount: showCounts),
                              )
                              .toList(),
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
                    ref,
                    grouped: true,
                    _groupedBody(
                      useTabs: useTabs,
                      sections: _groupSections(tabs),
                      byCategory: false,
                      showCounts: showCounts,
                      tabViews: () => tabs.map((t) {
                        final content = _GroupedMangaList(
                          key: ValueKey(t.id),
                          tabId: t.id,
                        );
                        return showInlineHeaders
                            ? _PagedSection(
                                key: ValueKey(t.id),
                                section: (id: t.id, name: t.name),
                                byCategory: false,
                                showCount: showCounts,
                                child: content,
                              )
                            : content;
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      refresh: () {
        ref.read(viewOfflineNowProvider.notifier).set(false);
        ref.read(serverUnreachableProvider.notifier).set(false);
        ref.invalidate(libraryGroupedTabsProvider);
      },
      // Changing the grouping type reloads this provider; keep the current
      // tabs — and their Scaffold's endDrawer — up instead of flashing the
      // spinner Scaffold below.
      skipLoadingOnReload: true,
      wrapper: (body) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.library)),
        body: _libraryBody(ref, body, grouped: true),
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

/// A Tab for one non-default group (source, status, tag, language, …). Mirrors
/// [_CategoryTab], counting from the same filtered provider the tab body reads.
class _GroupTab extends ConsumerWidget {
  const _GroupTab({required this.tab, required this.showCount});
  final GroupedTab tab;
  final bool showCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!showCount) return Tab(text: tab.name);
    final count = ref
        .watch(groupedMangaListWithQueryAndFilterProvider(tabId: tab.id))
        .value
        ?.length;
    return Tab(text: count != null ? '${tab.name} ($count)' : tab.name);
  }
}

/// One page of a paginated Section-Headers library: an inline, non-sticky
/// header above that section's content.
class _PagedSection extends ConsumerWidget {
  const _PagedSection({
    super.key,
    required this.section,
    required this.byCategory,
    required this.showCount,
    required this.child,
  });

  final LibrarySection section;
  final bool byCategory;
  final bool showCount;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var title = section.name;
    if (showCount) {
      final listAsync = byCategory
          ? ref.watch(
              categoryMangaListWithQueryAndFilterProvider(
                categoryId: section.id,
              ),
            )
          : ref.watch(
              groupedMangaListWithQueryAndFilterProvider(tabId: section.id),
            );
      final count = listAsync.value?.length;
      if (count != null) title = '$title ($count)';
    }
    return Column(
      children: [
        Container(
          height: 40,
          width: double.infinity,
          color: context.theme.colorScheme.surface,
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: context.theme.textTheme.titleSmall?.copyWith(
              color: context.theme.colorScheme.primary,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
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

    return mangaListAsync.showUiWhenData(
      context,
      loadingWidget: const OfflineViewLoading(),
      offlineEscapeHatch: true,
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
            unawaited(
              ref
                  .read(updatesRepositoryProvider)
                  .fetchUpdates()
                  .catchError((Object _) {}),
            );
            ref.invalidate(libraryMangaListProvider);
            await ref.read(libraryMangaListProvider.future);
          },
          child: LibraryMangaGridView(
            items: items,
            onOpen: (manga) => MangaRoute(mangaId: manga.id).push(context),
          ),
        );
      },
      refresh: () {
        ref.read(viewOfflineNowProvider.notifier).set(false);
        ref.read(serverUnreachableProvider.notifier).set(false);
        ref.invalidate(libraryMangaListProvider);
      },
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

/// "Library", plus a subtitle naming the section on screen while scrolling a
/// continuous Section-Headers library. Tab mode and single-section libraries
/// have nothing to disambiguate, so they get no subtitle.
class _LibraryTitle extends ConsumerWidget {
  const _LibraryTitle({required this.sections});
  final List<LibrarySection> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style =
        ref.watch(libraryGroupStyleKeyProvider) ?? LibraryGroupStyle.tabs;
    final showAllCategories = ref
        .watch(sectionHeadersShowAllCategoriesProvider)
        .ifNull(false);
    // Continuous scroll only — paginated pages carry their own inline header.
    final isSectionHeaders = !_useTabs(style, showAllCategories);
    final visibleId = ref.watch(libraryVisibleSectionProvider);
    final visibleName = isSectionHeaders && sections.length > 1
        ? sections.firstWhereOrNull((s) => s.id == visibleId)?.name
        : null;

    final title = Text(context.l10n.library);
    if (visibleName == null) return title;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        Text(
          visibleName,
          overflow: TextOverflow.ellipsis,
          style: context.theme.textTheme.bodySmall?.copyWith(
            color: context.theme.appBarTheme.foregroundColor?.withValues(
              alpha: .7,
            ),
          ),
        ),
      ],
    );
  }
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
            onPressed: () => openGlobalSearch(context, query: query),
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
