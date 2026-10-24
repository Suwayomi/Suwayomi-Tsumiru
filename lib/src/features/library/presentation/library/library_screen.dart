// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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
import 'widgets/library_random_entry.dart';
import 'widgets/library_sections_view.dart';

/// Keeps the mismatch banner inside the body; [grouped] chooses the provider Retry refreshes.
/// [header] stays fixed above banners.
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

List<LibrarySection> _categorySections(List<CategoryDto> categories) => [
  for (final c in categories)
    (id: c.id.getValueOnNullOrNegative(), name: c.name),
];

List<LibrarySection> _groupSections(List<GroupedTab> tabs) => [
  for (final t in tabs) (id: t.id, name: t.name),
];

bool _useTabs(LibraryGroupStyle style, bool showAllCategories) =>
    style == LibraryGroupStyle.tabs || !showAllCategories;

bool _showTabBar(LibraryGroupStyle style, bool categoryTabsOn) =>
    style == LibraryGroupStyle.tabs && categoryTabsOn;

bool _showInlineHeaders(LibraryGroupStyle style, bool showAllCategories) =>
    style == LibraryGroupStyle.headers && !showAllCategories;

Widget _groupedBody({
  required bool useTabs,
  required List<LibrarySection> sections,
  required bool byCategory,
  required bool showCounts,
  required List<Widget> Function() tabViews,
}) => Builder(
  builder: (context) => Padding(
    // Desktop slivers reserve a scrollbar gutter on the right.
    padding: context.usesDesktopShell
        ? const EdgeInsets.only(left: 8)
        : KEdgeInsets.h8.size,
    child: useTabs
        ? Builder(
            builder: (context) {
              final tabs = tabViews();
              if (!context.usesDesktopShell) {
                // Tabs share the ambient controller here; scrollbars would attach to multiple positions.
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

/// Gives each desktop tab its own controller so the scrollbar attaches to only one position.
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

    // Seed from the current socket state; refresh on running→idle and ignore reconnect nulls.
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


/// Refreshes the library after a watched SyncYomi sync may have changed entries or categories.
void _refreshLibraryAfterSync(WidgetRef ref) {
  ref.invalidate(libraryMangaListProvider);
  ref.invalidate(categoryControllerProvider);
}

/// Build under DefaultTabController so the toolbar and strip share the body's tab index.
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
          // The organizer sizes itself to the active tab, capped at 72% of screen height.
          builder: (_) => const LibraryMangaOrganizer(),
          sheetAnimationStyle: context.motionStyle,
        );
      }
    },
    icon: const Icon(FluentIcons.filter_24_regular),
  ),
);

/// Recheck after builds as refresh can change header extent without a scroll event.
/// Missing or zero-height search bars are not hidden; this avoids two visible fields.
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


class _DefaultLibraryScreen extends ConsumerWidget {
  const _DefaultLibraryScreen({required this.categoryId});
  final int categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(libraryPersistentSearchBarProvider).ifNull()
      ? _DefaultLibraryStickySearch(categoryId: categoryId)
      : _DefaultLibraryToggledSearch(categoryId: categoryId);
}

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
    final phone = context.windowSizeClass == WindowSizeClass.compact;
    final showSearch =
        searchToggled.value || ref.watch(libraryQueryProvider).isNotBlank;
    final desktop = context.usesDesktopShell;
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
            // Recreate the controller when categories change; active drags must not retain disposed animations.
            key: ValueKey('categories-${data!.map((c) => c.id).join(',')}'),
            length: data.length,
            animationDuration: context.reduceMotion
                ? Duration.zero
                : kTabScrollDuration,
            // Route params are category IDs, not visible-tab indices; hidden/empty categories shift positions.
            initialIndex: max(0, data.indexWhere((c) => c.id == categoryId)),
            child: Scaffold(
              appBar: desktop
                  ? null
                  : AppBar(
                      title: phone || !showSearch
                          ? _LibraryTitle(sections: _categorySections(data))
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
                                  // Programmatic tag searches must not steal focus and open the keyboard.
                                  autofocus: searchToggled.value,
                                  onChanged: (val) => ref
                                      .read(libraryQueryProvider.notifier)
                                      .update(val),
                                  onClose: () => searchToggled.value = false,
                                  actions: [
                                    IconButton(
                                      icon: const Icon(
                                        FluentIcons.question_circle_24_regular,
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
                                  icon: const Icon(FluentIcons.search_24_regular),
                                ),
                              _organizerButton(),
                              SyncYomiSyncButton(
                                onSynced: () => _refreshLibraryAfterSync(ref),
                              ),
                              Builder(
                                builder: (context) {
                                  return UpdateStatusPopupMenu(
                                    // Section headers have no current tab, so update the whole library.
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
                  // Capture this controller: shell-bar content lives outside its DefaultTabController.
                  final tabController = DefaultTabController.of(bodyContext);
                  final trailing = <Widget>[
                    LibraryRandomEntryButton(libraryContext: bodyContext),
                    SyncYomiSyncButton(
                      onSynced: () => _refreshLibraryAfterSync(ref),
                    ),
                    UpdateStatusPopupMenu(
                      // Section headers have no current tab, so update the whole library.
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
        final desktop = context.usesDesktopShell;
        final topBar = showsMergedTopBar(context);
        final phone = context.windowSizeClass == WindowSizeClass.compact;

        return DefaultTabController(
          // Recreate the controller when categories change; active drags must not retain disposed animations.
          key: ValueKey('categories-${data.map((c) => c.id).join(',')}'),
          length: data.length,
          animationDuration: context.reduceMotion
              ? Duration.zero
              : kTabScrollDuration,
          // Route params are category IDs, not visible-tab indices; hidden/empty categories shift positions.
          initialIndex: max(0, data.indexWhere((c) => c.id == categoryId)),
          child: Scaffold(
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
                // Capture this controller: shell-bar content lives outside its DefaultTabController.
                final tabController = DefaultTabController.of(bodyContext);
                final trailing = <Widget>[
                  LibraryRandomEntryButton(libraryContext: bodyContext),
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
                            // Section headers have no current tab, so update the whole library.
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
              // Remove the status-bar inset inside the body MediaQuery; header slivers already consume it.
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


class _GroupedLibraryScreen extends ConsumerWidget {
  const _GroupedLibraryScreen({required this.groupType});
  final int groupType;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(libraryPersistentSearchBarProvider).ifNull()
      ? _GroupedLibraryStickySearch(groupType: groupType)
      : _GroupedLibraryToggledSearch(groupType: groupType);
}

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
    final phone = context.windowSizeClass == WindowSizeClass.compact;
    final showSearch =
        searchToggled.value || ref.watch(libraryQueryProvider).isNotBlank;
    final desktop = context.usesDesktopShell;
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
          // Recreate the controller when tab IDs change so the selected index remains valid.
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
                                      FluentIcons.question_circle_24_regular,
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
                                icon: const Icon(FluentIcons.search_24_regular),
                              ),
                            IconButton(
                              tooltip: context.l10n.migrationPickSourceTitle,
                              onPressed: () =>
                                  const MigrationSourcePickerRoute().push(
                                    context,
                                  ),
                              icon: const Icon(FluentIcons.arrow_swap_24_regular),
                            ),
                            _organizerButton(),
                            Consumer(
                              builder: (context, ref, _) =>
                                  PopupMenuButton<void>(
                                    icon: const Icon(
                                      FluentIcons.more_vertical_24_regular,
                                    ),
                                    itemBuilder: (_) => [
                                      PopupMenuItem<void>(
                                        onTap: randomLibraryEntryAction(
                                          context,
                                          ref,
                                        ),
                                        child: Text(
                                          context.l10n.openRandomEntry,
                                        ),
                                      ),
                                    ],
                                  ),
                            ),
                            SyncYomiSyncButton(
                              onSynced: () => _refreshLibraryAfterSync(ref),
                            ),
                          ],
                  ),
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
                final trailing = <Widget>[
                  LibraryRandomEntryButton(libraryContext: bodyContext),
                  IconButton(
                    tooltip: bodyContext.l10n.migrationPickSourceTitle,
                    onPressed: () =>
                        const MigrationSourcePickerRoute().push(context),
                    icon: const Icon(FluentIcons.arrow_swap_24_regular),
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
      // Keep current tabs and their endDrawer visible while the new grouping loads.
      skipLoadingOnReload: true,
      wrapper: (body) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.library)),
        body: _libraryBody(ref, body, grouped: true),
      ),
    );
  }
}

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
    final desktop = context.usesDesktopShell;
    final topBar = showsMergedTopBar(context);
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
          // Recreate the controller when tab IDs change so the selected index remains valid.
          key: ValueKey('group-$groupType-${tabs.length}'),
          length: tabs.length,
          animationDuration: context.reduceMotion
              ? Duration.zero
              : kTabScrollDuration,
          child: Scaffold(
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
                final trailing = <Widget>[
                  LibraryRandomEntryButton(libraryContext: bodyContext),
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
                            Consumer(
                              builder: (context, ref, _) =>
                                  PopupMenuButton<void>(
                                    icon: const Icon(
                                      FluentIcons.more_vertical_24_regular,
                                    ),
                                    itemBuilder: (_) => [
                                      PopupMenuItem<void>(
                                        onTap: randomLibraryEntryAction(
                                          context,
                                          ref,
                                        ),
                                        child: Text(
                                          context.l10n.openRandomEntry,
                                        ),
                                      ),
                                    ],
                                  ),
                            ),
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
              // Remove the body's status-bar inset; header slivers already consume it.
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
      // Keep current tabs and their endDrawer visible while the new grouping loads.
      skipLoadingOnReload: true,
      wrapper: (body) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.library)),
        body: _libraryBody(ref, body, grouped: true),
      ),
    );
  }
}


/// Counts use the filtered list, including offline data, rather than server totalCount.
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

/// Counts use the same filtered provider as the group's body.
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
          // Grouped tabs have no single category; pull checks the whole library.
          onRefresh: () async {
            ref.read(updateOptimisticProvider.notifier).arm();
            unawaited(
              ref
                  .read(updatesRepositoryProvider)
                  .fetchUpdates()
                  .catchError((Object _) {}),
            );
            // Refresh categories too, since another client can add them between launches.
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
          icon: const Icon(FluentIcons.question_circle_24_regular),
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

  // Compare TabBar instances so rebuilt headers reflect renamed or added categories.
  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar;
}
