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
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/search_field.dart';
import '../../../../widgets/shell/update_banner_state.dart';
import '../../../manga_book/data/updates/updates_repository.dart';
import '../../../manga_book/widgets/update_status_popup_menu.dart';
import '../../../offline/data/server_reachability.dart';
import '../../../offline/presentation/offline_server_mismatch_banner.dart';
import '../../../offline/presentation/offline_view_loading.dart';
import '../../../offline/presentation/server_unreachable_banner.dart';
import '../../../quick_open/presentation/unified_search/phone_search_view.dart';
import '../../../settings/presentation/library/widgets/persistent_search_bar/persistent_search_bar.dart';
import '../../../settings/presentation/syncyomi/syncyomi_sync.dart';
import '../../domain/category/category_model.dart';
import '../../domain/library_group.dart';
import '../category/controller/edit_category_controller.dart';
import 'category_manga_list.dart';
import 'controller/library_controller.dart';
import 'controller/library_grouping.dart';
import 'controller/library_manga_list.dart';
import 'widgets/category_tab_strip.dart';
import 'widgets/desktop_library_toolbar.dart';
import 'widgets/library_manga_grid_view.dart';
import 'widgets/library_manga_organizer.dart';
import 'widgets/library_sections_view.dart';

/// Wraps a library Scaffold body so the offline server-mismatch banner sits
/// below the app bar (inside the Scaffold), not floating over the status bar.
/// [grouped] picks what the banner's Retry re-asks for: the two library screens
/// draw their tabs from different providers, and refreshing the other one left
/// the content stale while the banner vanished.
/// [header] is the desktop toolbar + tab strip, fixed above the banners.
Widget _libraryBody(
  WidgetRef ref,
  Widget body, {
  bool grouped = false,
  Widget? header,
}) => Column(
  children: [
    ?header,
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
}) => Builder(
  builder: (context) => Padding(
    // Desktop runs the scroll view to the content area's right edge so the
    // always-visible themed scrollbar travels in the gutter the slivers keep
    // (see LibraryMangaSliver); the left inset stays as before. Phone/tablet
    // keep the symmetric inset.
    padding: context.windowSizeClass >= WindowSizeClass.medium
        ? const EdgeInsets.only(left: 8)
        : KEdgeInsets.h8.size,
    child: useTabs
        ? Builder(
            builder: (context) {
              final tabs = tabViews();
              if (context.windowSizeClass == WindowSizeClass.compact) {
                // Tabs share the ambient controller here, so no scrollbars (else "attached to more than one ScrollPosition").
                return ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: TabBarView(children: tabs),
                );
              }
              return TabBarView(
                children: [for (final tab in tabs) _TabScrollHost(child: tab)],
              );
            },
          )
        : LibrarySectionsView(
            sections: sections,
            byCategory: byCategory,
            showCounts: showCounts,
          ),
  ),
);

/// Gives one library tab its own primary scroll controller on desktop, so the
/// themed scrollbar never sees two tabs sharing the ambient controller (the
/// "attached to more than one ScrollPosition" assertion). Phone and tablet
/// keep the shared controller exactly as before.
class _TabScrollHost extends HookWidget {
  const _TabScrollHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = useScrollController();
    return PrimaryScrollController(controller: controller, child: child);
  }
}

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
    //
    // Seeded from the socket's current value so an update already in progress
    // when this widget mounts (e.g. user navigates to Library mid-update)
    // correctly triggers the invalidate when it finishes, instead of missing
    // the true→false edge because lastRunning started at false.
    final lastRunning = useRef<bool>(
      ref.read(updateRunningSocketProvider).value ?? false,
    );
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

/// Re-reads the library once a SyncYomi sync this app started or watched run
/// finishes: the sync may have added entries or moved them between categories.
void _refreshLibraryAfterSync(WidgetRef ref) {
  ref.invalidate(libraryMangaListProvider);
  ref.invalidate(categoryControllerProvider);
}

/// Desktop page header: the toolbar row plus the category strip when tabs
/// show. Built under the DefaultTabController (so the overflow menu and strip
/// share the tab index with the TabBarView). The toolbar's Filter/Display
/// buttons open anchored panels, so desktop needs no end drawer.
Widget _desktopLibraryHeader({
  required List<Widget> trailing,
  Widget? tabStrip,
}) => Builder(
  builder: (context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DesktopLibraryToolbar(trailing: trailing),
      ?tabStrip,
    ],
  ),
);

/// Filter/sort/display organizer button: end-drawer on tablets, bottom sheet
/// on phones.
Widget _organizerButton() => Builder(
  builder: (context) => IconButton(
    onPressed: () {
      if (context.windowSizeClass >= WindowSizeClass.medium) {
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
          sheetAnimationStyle: context.motionStyle,
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
    // Phone searches from the app-bar entry instead, which applies to the
    // filter on submit.
    final phone = context.windowSizeClass == WindowSizeClass.compact;
    final showSearch =
        searchToggled.value || ref.watch(libraryQueryProvider).isNotBlank;
    // Desktop replaces the app bar + TabBar with the toolbar + tab strip.
    final desktop = context.windowSizeClass >= WindowSizeClass.medium;
    // Native desktop draws the toolbar in the shell bar instead of the body.
    final topBar = showsMergedTopBar(context);
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
            title: context.l10n.noVisibleCategories,
            button: TextButton(
              onPressed: () => const EditCategoriesRoute().push(context),
              child: Text(context.l10n.categories),
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
            animationDuration: context.reduceMotion
                ? Duration.zero
                : kTabScrollDuration,
            // The route param is a category ID (e.g. from quick-search), not a
            // positional tab index — the visible list filters out empty/hidden
            // categories, so id != index. Select the tab whose category matches
            // the id, falling back to the first tab if it isn't visible (#284).
            initialIndex: max(0, data.indexWhere((c) => c.id == categoryId)),
            child: Scaffold(
              appBar: desktop
                  ? null
                  : AppBar(
                      title: phone || !showSearch
                          ? _LibraryTitle(sections: _categorySections(data))
                          // SearchField no longer pads itself; keep the pre-refactor
                          // inset and large-tablet width cap here.
                          : SizedBox(
                              width: context.windowSizeClass >=
                                      WindowSizeClass.expanded
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
                                      icon: const Icon(
                                        Icons.help_outline_rounded,
                                      ),
                                      tooltip: context.l10n.searchTips,
                                      onPressed: () => showSearchTips(context),
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
                      actions: showSearch && !phone
                          ? const [SizedBox.shrink()]
                          : [
                              if (phone) ...[
                                const PhoneSearchClearFilter(
                                  origin: PhoneSearchOrigin.library,
                                ),
                                const PhoneSearchEntry(
                                  origin: PhoneSearchOrigin.library,
                                ),
                              ] else
                                IconButton(
                                  onPressed: () => searchToggled.value = true,
                                  icon: const Icon(Icons.search_rounded),
                                ),
                              _organizerButton(),
                              SyncYomiSyncButton(
                                onSynced: () => _refreshLibraryAfterSync(ref),
                              ),
                              Builder(
                                builder: (context) {
                                  return UpdateStatusPopupMenu(
                                    // Section-headers style has no "current" tab, so
                                    // the menu targets the whole library there.
                                    getCategory: () =>
                                        useTabs && data.isNotBlank
                                        ? data[DefaultTabController.of(
                                            context,
                                          ).index]
                                        : null,
                                    showDuplicatesButton: true,
                                  );
                                },
                              ),
                            ],
                    ),
              // Desktop uses the toolbar's anchored panels instead of the
              // drawer; tablet keeps the end drawer via _organizerButton.
              endDrawerEnableOpenDragGesture: false,
              endDrawer: desktop
                  ? null
                  : const Drawer(
                      width: kDrawerWidth,
                      shape: RoundedRectangleBorder(),
                      child: LibraryMangaOrganizer(),
                    ),
              body: Builder(
                builder: (bodyContext) {
                  // The slot content shows in the shell bar outside this tab
                  // controller: capture the controller now, so the update
                  // menu targets the current tab even from the bar.
                  final tabController = DefaultTabController.of(bodyContext);
                  final trailing = <Widget>[
                    SyncYomiSyncButton(
                      onSynced: () => _refreshLibraryAfterSync(ref),
                    ),
                    UpdateStatusPopupMenu(
                      // Section-headers style has no "current" tab, so the
                      // menu targets the whole library there.
                      getCategory: () => useTabs && data.isNotBlank
                          ? data[tabController.index]
                          : null,
                      showDuplicatesButton: true,
                    ),
                  ];
                  final tabStrip =
                      showTabBar && data.length.isGreaterThan(1)
                          ? DefaultCategoryTabStrip(categories: data)
                          : null;
                  return TopBarSlot(
                    content: DesktopLibraryToolbar(trailing: trailing),
                    minWidth: libraryTopBarSlotMinWidth(trailing.length),
                    child: _libraryBody(
                    ref,
                    header: topBar
                        ? tabStrip
                        : desktop
                        ? _desktopLibraryHeader(
                            trailing: trailing,
                            tabStrip: tabStrip,
                          )
                        : null,
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
                );
              },
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
              title: context.l10n.noVisibleCategories,
              button: TextButton(
                onPressed: () => const EditCategoriesRoute().push(context),
                child: Text(context.l10n.categories),
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
        // Desktop replaces the sliver app bar + TabBar with the toolbar row
        // and the tab strip, both pinned.
        final desktop = context.windowSizeClass >= WindowSizeClass.medium;
        // Native desktop draws the toolbar in the shell bar instead of the
        // pinned header.
        final topBar = showsMergedTopBar(context);
        // Phone searches from the box under the title, applied to the filter
        // on submit; tablet keeps the live sticky bar.
        final phone = context.windowSizeClass == WindowSizeClass.compact;

        return DefaultTabController(
          // See the matching comment on the toggled-search variant above: keys
          // the controller to the category set so it fully rebuilds instead of
          // swapping its length under an in-flight drag.
          key: ValueKey('categories-${data.map((c) => c.id).join(',')}'),
          length: data.length,
          animationDuration: context.reduceMotion
              ? Duration.zero
              : kTabScrollDuration,
          // The route param is a category ID (e.g. from quick-search), not a
          // positional tab index — the visible list filters out empty/hidden
          // categories, so id != index. Select the tab whose category matches
          // the id, falling back to the first tab if it isn't visible (#284).
          initialIndex: max(0, data.indexWhere((c) => c.id == categoryId)),
          child: Scaffold(
            // Desktop uses the toolbar's anchored panels instead of the
            // drawer; tablet keeps the end drawer via _organizerButton.
            endDrawerEnableOpenDragGesture: false,
            endDrawer: desktop
                ? null
                : const Drawer(
                    width: kDrawerWidth,
                    shape: RoundedRectangleBorder(),
                    child: LibraryMangaOrganizer(),
                  ),
            body: Builder(
              builder: (bodyContext) {
                // The slot content shows in the shell bar outside this tab
                // controller: capture the controller now, so the update
                // menu targets the current tab even from the bar.
                final tabController = DefaultTabController.of(bodyContext);
                final trailing = <Widget>[
                  SyncYomiSyncButton(
                    onSynced: () => _refreshLibraryAfterSync(ref),
                  ),
                  UpdateStatusPopupMenu(
                    getCategory: () => useTabs && data.isNotBlank
                        ? data[tabController.index]
                        : null,
                    showDuplicatesButton: true,
                  ),
                ];
                final tabStrip = showTabs
                    ? DefaultCategoryTabStrip(categories: data)
                    : null;
                return TopBarSlot(
                  content: DesktopLibraryToolbar(trailing: trailing),
                  minWidth: libraryTopBarSlotMinWidth(trailing.length),
                  child: NestedScrollView(
                    controller: scrollController,
                    headerSliverBuilder: (context, innerBoxIsScrolled) {
                      if (topBar) {
                        // Tabs stay pinned in the page body under the bar;
                        // the toolbar row itself lives in the shell bar.
                        if (tabStrip == null) return [];
                        return [
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _SliverFixedHeaderDelegate(
                              height: 44,
                              child: tabStrip,
                            ),
                          ),
                        ];
                      }
                      if (desktop) {
                        return [
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _SliverFixedHeaderDelegate(
                              height: showTabs ? 64 + 44 : 64,
                        child: _desktopLibraryHeader(
                          trailing: trailing,
                          tabStrip: tabStrip,
                        ),
                      ),
                    ),
                  ];
                }
                return [
                  SliverAppBar(
                    pinned: true,
                    floating: false,
                    title: phone || !isSearchBarHidden
                        ? _LibraryTitle(sections: _categorySections(data))
                        : const _LibrarySearchBar(inAppBar: true),
                    bottom: phone
                        ? const PhoneSearchBoxBottom(
                            origin: PhoneSearchOrigin.library,
                          )
                        : null,
                    actions: [
                      _organizerButton(),
                      SyncYomiSyncButton(
                        onSynced: () => _refreshLibraryAfterSync(ref),
                      ),
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
                  if (!phone)
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
          );
        },
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
    // Phone searches from the app-bar entry instead, which applies to the
    // filter on submit.
    final phone = context.windowSizeClass == WindowSizeClass.compact;
    final showSearch =
        searchToggled.value || ref.watch(libraryQueryProvider).isNotBlank;
    // Desktop replaces the app bar + TabBar with the toolbar + tab strip.
    final desktop = context.windowSizeClass >= WindowSizeClass.medium;
    // Native desktop draws the toolbar in the shell bar instead of the body.
    final topBar = showsMergedTopBar(context);
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
              title: context.l10n.noVisibleCategories,
              button: TextButton(
                onPressed: () => const EditCategoriesRoute().push(context),
                child: Text(context.l10n.categories),
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
          animationDuration: context.reduceMotion
              ? Duration.zero
              : kTabScrollDuration,
          child: Scaffold(
            appBar: desktop
                ? null
                : AppBar(
                    title: phone || !showSearch
                        ? _LibraryTitle(sections: _groupSections(tabs))
                        // SearchField no longer pads itself; keep the pre-refactor
                        // inset and large-tablet width cap here.
                        : SizedBox(
                            width: context.windowSizeClass >=
                                    WindowSizeClass.expanded
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
                                    icon: const Icon(
                                      Icons.help_outline_rounded,
                                    ),
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
                                .map(
                                  (t) =>
                                      _GroupTab(tab: t, showCount: showCounts),
                                )
                                .toList(),
                            dividerColor: Colors.transparent,
                          )
                        : null,
                    actions: showSearch && !phone
                        ? const [SizedBox.shrink()]
                        : [
                            if (phone) ...[
                              const PhoneSearchClearFilter(
                                origin: PhoneSearchOrigin.library,
                              ),
                              const PhoneSearchEntry(
                                origin: PhoneSearchOrigin.library,
                              ),
                            ] else
                              IconButton(
                                onPressed: () => searchToggled.value = true,
                                icon: const Icon(Icons.search_rounded),
                              ),
                            IconButton(
                              tooltip: context.l10n.migrationPickSourceTitle,
                              onPressed: () =>
                                  const MigrationSourcePickerRoute().push(
                                    context,
                                  ),
                              icon: const Icon(Icons.swap_horiz_rounded),
                            ),
                            _organizerButton(),
                            SyncYomiSyncButton(
                              onSynced: () => _refreshLibraryAfterSync(ref),
                            ),
                          ],
                  ),
            // Desktop uses the toolbar's anchored panels instead of the
            // drawer; tablet keeps the end drawer via _organizerButton.
            endDrawerEnableOpenDragGesture: false,
            endDrawer: desktop
                ? null
                : const Drawer(
                    width: kDrawerWidth,
                    shape: RoundedRectangleBorder(),
                    child: LibraryMangaOrganizer(),
                  ),
            body: Builder(
              builder: (bodyContext) {
                // Native desktop draws the toolbar in the shell bar: register
                // it as this route's slot and keep only the tab strip in the
                // body. This variant's trailing needs no tab controller.
                final trailing = <Widget>[
                  IconButton(
                    tooltip: bodyContext.l10n.migrationPickSourceTitle,
                    onPressed: () =>
                        const MigrationSourcePickerRoute().push(context),
                    icon: const Icon(Icons.swap_horiz_rounded),
                  ),
                  SyncYomiSyncButton(
                    onSynced: () => _refreshLibraryAfterSync(ref),
                  ),
                ];
                final tabStrip = showTabBar && tabs.length > 1
                    ? GroupedCategoryTabStrip(groupedTabs: tabs)
                    : null;
                return TopBarSlot(
                  content: DesktopLibraryToolbar(trailing: trailing),
                  minWidth: libraryTopBarSlotMinWidth(trailing.length),
                  child: _libraryBody(
                    ref,
                    grouped: true,
                    header: topBar
                        ? tabStrip
                        : desktop
                        ? _desktopLibraryHeader(
                            trailing: trailing,
                            tabStrip: tabStrip,
                          )
                        : null,
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
          );
        },
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
    // Desktop replaces the sliver app bar + TabBar with the toolbar row
    // and the tab strip, both pinned.
    final desktop = context.windowSizeClass >= WindowSizeClass.medium;
    // Native desktop draws the toolbar in the shell bar instead of the
    // pinned header.
    final topBar = showsMergedTopBar(context);
    // Phone searches from the box under the title, applied to the filter
    // on submit; tablet keeps the live sticky bar.
    final phone = context.windowSizeClass == WindowSizeClass.compact;

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
              title: context.l10n.noVisibleCategories,
              button: TextButton(
                onPressed: () => const EditCategoriesRoute().push(context),
                child: Text(context.l10n.categories),
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
          animationDuration: context.reduceMotion
              ? Duration.zero
              : kTabScrollDuration,
          child: Scaffold(
            // Desktop uses the toolbar's anchored panels instead of the
            // drawer; tablet keeps the end drawer via _organizerButton.
            endDrawerEnableOpenDragGesture: false,
            endDrawer: desktop
                ? null
                : const Drawer(
                    width: kDrawerWidth,
                    shape: RoundedRectangleBorder(),
                    child: LibraryMangaOrganizer(),
                  ),
            body: Builder(
              builder: (bodyContext) {
                // Native desktop draws the toolbar in the shell bar: register
                // it as this route's slot and keep only the tab strip pinned.
                // This variant's trailing needs no tab controller.
                final trailing = <Widget>[
                  SyncYomiSyncButton(
                    onSynced: () => _refreshLibraryAfterSync(ref),
                  ),
                ];
                final tabStrip = showTabBar && tabs.length > 1
                    ? GroupedCategoryTabStrip(groupedTabs: tabs)
                    : null;
                return TopBarSlot(
                  content: DesktopLibraryToolbar(trailing: trailing),
                  minWidth: libraryTopBarSlotMinWidth(trailing.length),
                  child: NestedScrollView(
                    controller: scrollController,
                    headerSliverBuilder: (context, innerBoxIsScrolled) {
                      if (topBar) {
                        // Tabs stay pinned in the page body under the bar;
                        // the toolbar row itself lives in the shell bar.
                        if (tabStrip == null) return [];
                        return [
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _SliverFixedHeaderDelegate(
                              height: 44,
                              child: tabStrip,
                            ),
                          ),
                        ];
                      }
                      if (desktop) {
                        return [
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _SliverFixedHeaderDelegate(
                              height: showTabBar && tabs.length > 1
                                  ? 64 + 44
                                  : 64,
                        child: _desktopLibraryHeader(
                          trailing: trailing,
                          tabStrip: tabStrip,
                        ),
                      ),
                    ),
                  ];
                }
                return [
                  SliverAppBar(
                    pinned: true,
                    floating: false,
                    title: phone || !isSearchBarHidden
                        ? _LibraryTitle(sections: _groupSections(tabs))
                        : const _LibrarySearchBar(inAppBar: true),
                    bottom: phone
                        ? const PhoneSearchBoxBottom(
                            origin: PhoneSearchOrigin.library,
                          )
                        : null,
                    actions: [
                      _organizerButton(),
                      SyncYomiSyncButton(
                        onSynced: () => _refreshLibraryAfterSync(ref),
                      ),
                    ],
                  ),
                  if (!phone)
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
          );
        },
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
            // Categories are fetched once per launch, so one added in the
            // WebUI could not appear without restarting the app.
            ref.invalidate(categoryControllerProvider);
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

/// A pinned sliver of fixed [height] hosting the desktop toolbar + tab strip.
class _SliverFixedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SliverFixedHeaderDelegate({required this.height, required this.child});
  final double height;
  final Widget child;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_SliverFixedHeaderDelegate oldDelegate) =>
      height != oldDelegate.height || child != oldDelegate.child;
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
