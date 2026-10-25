// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../constants/db_keys.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/hooks/paging_controller_hook.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/custom_circular_progress_indicator.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/emoticons.dart';
import '../../../library/presentation/library/controller/library_controller.dart';
import '../../../library/presentation/library/widgets/desktop_library_panels.dart';
import '../../../library/presentation/library/widgets/desktop_library_toolbar.dart';
import '../../../quick_open/presentation/unified_search/desktop_search_field.dart';
import '../../../quick_open/presentation/unified_search/phone_search_view.dart';
import '../../../quick_open/presentation/unified_search/unified_search_providers.dart';
import '../../../settings/presentation/appearance/widgets/grid_cover_width_slider/grid_cover_width_slider.dart';
import '../../../settings/presentation/library/widgets/persistent_search_bar/persistent_search_bar.dart';
import '../../../settings/presentation/syncyomi/syncyomi_sync.dart';
import '../../data/updates/updates_repository.dart';
import '../../domain/chapter/chapter_model.dart';
import '../../domain/chapter/graphql/__generated__/fragment.graphql.dart';
import '../../domain/updates/updates_grouping.dart';
import '../../domain/updates/updates_row_patch.dart';
import '../../widgets/chapter_actions/multi_chapters_actions_bottom_app_bar.dart';
import '../../widgets/update_status_fab.dart';
import '../../widgets/update_status_popup_menu.dart';
import '../manga_details/controller/manga_details_controller.dart';
import '../manga_details/widgets/chapter_selection_header.dart';
import '../reader/controller/reader_controller.dart';
import 'controller/updates_filter_controller.dart';
import 'controller/updates_grouping_controller.dart';
import 'widgets/chapter_manga_grouped_tile.dart';
import 'widgets/chapter_manga_list_tile.dart';
import 'widgets/updates_filter.dart';
import 'widgets/updates_filter_content.dart';
import 'widgets/updates_grid_card.dart';
import 'widgets/updates_row_actions.dart';

const _kUpdatesCardSubtitleExtent = 22.0;


Widget _updatesColumn(Widget child) => Align(
  alignment: Alignment.topCenter,
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 1040),
    child: SizedBox(width: double.infinity, child: child),
  ),
);

Widget _lastUpdatedLine(BuildContext context, String lastUpdated) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  child: Text(
    context.l10n.libraryLastUpdated(int.parse(lastUpdated).toTimeAgo(context)),
    style: context.textTheme.bodyMedium?.copyWith(
      fontStyle: FontStyle.italic,
      color: context.theme.colorScheme.onSurfaceVariant,
    ),
  ),
);

class _UpdatesPagedList extends StatefulWidget {
  const _UpdatesPagedList({
    required this.controller,
    required this.groupingMode,
    required this.displayMode,
    required this.gridWidth,
    required this.fixedColumns,
    required this.selectedChapters,
    required this.selectionAnchor,
    required this.getGeneration,
    required this.screenContext,
    required this.resetList,
    required this.refetchChapter,
  });

  final ServerPagingController<ChapterWithMangaDto> controller;
  final UpdatesGroupingMode groupingMode;
  final UpdatesDisplayMode displayMode;
  final double gridWidth;
  final int fixedColumns;
  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final ValueNotifier<int?> selectionAnchor;
  final ValueGetter<int> getGeneration;
  final BuildContext screenContext;
  final VoidCallback resetList;
  final Future<ChapterDto?> Function(int chapterId) refetchChapter;

  @override
  State<_UpdatesPagedList> createState() => _UpdatesPagedListState();
}

class _UpdatesPagedListState extends State<_UpdatesPagedList> {
  // Cache by pages identity, not items (a fresh flattened list), to group once per page set rather than per row.
  List<List<ChapterWithMangaDto>>? _memoPages;
  List<ChapterWithMangaDto>? _memoItems;
  List<UpdatesGroupedEntry>? _memoGroups;
  Map<int, int>? _memoHeadIndex;
  Set<int>? _memoHeaderIndices;
  Map<int, UpdatesDaySection>? _memoSections;

  ({
    List<ChapterWithMangaDto> items,
    List<UpdatesGroupedEntry> groups,
    Map<int, int> headIndex,
    Set<int> headerIndices,
    Map<int, UpdatesDaySection> sections,
  })
  _groupingFor(List<List<ChapterWithMangaDto>>? pages) {
    if (_memoPages != null && identical(_memoPages, pages)) {
      return (
        items: _memoItems!,
        groups: _memoGroups!,
        headIndex: _memoHeadIndex!,
        headerIndices: _memoHeaderIndices!,
        sections: _memoSections!,
      );
    }
    final items = [
      for (final page in pages ?? <List<ChapterWithMangaDto>>[]) ...page,
    ];
    final groups = groupUpdatesForDisplay(items);
    final headIndex = headFlatIndexToDisplayIndex(items, groups);
    final headerIndices = dateHeaderIndices(items);
    final sections = {
      for (final section in groupUpdatesByDay(items, groups))
        section.headerFlatIndex: section,
    };
    _memoPages = pages;
    _memoItems = items;
    _memoGroups = groups;
    _memoHeadIndex = headIndex;
    _memoHeaderIndices = headerIndices;
    _memoSections = sections;
    return (
      items: items,
      groups: groups,
      headIndex: headIndex,
      headerIndices: headerIndices,
      sections: sections,
    );
  }

  Future<void> _updatePair(ChapterWithMangaDto item) async {
    final chapter = await widget.refetchChapter(item.id);
    if (!widget.screenContext.mounted) return;
    widget.controller.mapItems(
      (row) => row.id != item.id
          ? row
          : row.copyWith(
              user: row.user.copyWith(
                isRead: (chapter?.user.isRead ?? false) || row.user.isRead,
                isDownloaded: chapter?.user.isDownloaded,
                lastPageRead: chapter?.user.lastPageRead,
              ),
            ),
    );
  }

  Future<void> _refreshManga(int mangaId) => _refreshMangas({mangaId});

  Future<void> _refreshMangas(
    Set<int> mangaIds, {
    bool freshWins = false,
  }) async {
    final startGeneration = widget.getGeneration();
    final ids = [
      for (final row in widget.controller.items ?? <ChapterWithMangaDto>[])
        if (mangaIds.contains(row.mangaId)) row.id,
    ];
    final chapters = await fetchChaptersInBatches(
      ids: ids,
      fetch: widget.refetchChapter,
    );
    if (!widget.screenContext.mounted ||
        widget.getGeneration() != startGeneration) {
      return;
    }
    final controller = widget.controller;
    var pages = controller.pages ?? <List<ChapterWithMangaDto>>[];
    for (final mangaId in mangaIds) {
      pages = [
        for (final page in pages)
          patchRowsForManga(
            rows: page,
            mangaId: mangaId,
            chapters: chapters,
            freshWins: freshWins,
          ),
      ];
    }
    controller.value = controller.value.copyWith(pages: pages);
  }

  void _toggleSelect(ChapterDto val) {
    if ((val.id).isNull) return;
    widget.selectedChapters.value = widget.selectedChapters.value.toggleKey(
      val.id,
      val,
    );
  }

  Widget _buildItem(
    BuildContext context,
    PagingState<int, ChapterWithMangaDto> state,
    int flatIndex,
  ) {
    final grouping = _groupingFor(state.pages);
    final items = grouping.items;

    if (context.usesDesktopShell &&
        widget.displayMode == UpdatesDisplayMode.grid) {
      final section = grouping.sections[flatIndex];
      if (section == null) return const SizedBox.shrink();
      return _buildDaySection(context, items, section);
    }

    final isGrouped = widget.groupingMode != UpdatesGroupingMode.disabled;

    if (isGrouped) {
      // A missing head index is already rendered in its group, so suppress the row.
      final displayIndex = grouping.headIndex[flatIndex];
      if (displayIndex == null) return const SizedBox.shrink();

      final group = grouping.groups[displayIndex];
      final tile = _buildGroupTile(context, group, items);
      return _wrapWithDateHeader(
        context,
        items,
        flatIndex,
        tile,
        grouping.headerIndices,
      );
    }

    final item = items[flatIndex];
    final tile = ChapterMangaListTile(
      chapterWithMangaDto: item,
      updatePair: () => _updatePair(item),
      refreshManga: () => _refreshManga(item.mangaId),
      refreshRowActions: (mangaIds) =>
          _refreshMangas(mangaIds, freshWins: true),
      isSelected: widget.selectedChapters.value.containsKey(item.id),
      canTapSelect: widget.selectedChapters.value.isNotEmpty,
      toggleSelect: (val) => _toggleSelect(val),
      selectedChapters: widget.selectedChapters,
      selectionAnchor: widget.selectionAnchor,
      orderedChapters: items,
      desktop: context.usesDesktopShell,
    );
    return _wrapWithDateHeader(
      context,
      items,
      flatIndex,
      tile,
      grouping.headerIndices,
    );
  }

  Widget _buildGroupTile(
    BuildContext context,
    UpdatesGroupedEntry group,
    List<ChapterWithMangaDto> items,
  ) {
    return ChapterMangaGroupedTile(
      head: group.head,
      tail: group.tail,
      updatePairFor: (chapter) =>
          () => _updatePair(chapter),
      refreshManga: () => _refreshManga(group.head.mangaId),
      refreshRowActions: (mangaIds) =>
          _refreshMangas(mangaIds, freshWins: true),
      isSelectedFor: (chapter) =>
          widget.selectedChapters.value.containsKey(chapter.id),
      canTapSelect: widget.selectedChapters.value.isNotEmpty,
      toggleSelect: (val) => _toggleSelect(val),
      selectedChapters: widget.selectedChapters,
      selectionAnchor: widget.selectionAnchor,
      orderedChapters: items,
      desktop: context.usesDesktopShell,
    );
  }

  Widget _buildDaySection(
    BuildContext context,
    List<ChapterWithMangaDto> items,
    UpdatesDaySection section,
  ) {
    final fetchedAt = int.tryParse(items[section.headerFlatIndex].fetchedAt);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fetchedAt != null)
          ListTile(title: Text(fetchedAt.toDaysAgoFromSeconds(context))),
        Padding(
          padding: context.usesDesktopShell
              ? const EdgeInsets.only(right: kDesktopScrollbarGutter)
              : EdgeInsets.zero,
          child: GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: mangaCoverUniformGridDelegate(
              widget.gridWidth,
              widget.fixedColumns,
              titleBelow: true,
              extraTitleExtent: _kUpdatesCardSubtitleExtent,
            ),
            children: [
              for (final group in section.groups)
                UpdatesGridCard(
                  group: group,
                  refreshManga: () => _refreshManga(group.head.mangaId),
                  refreshRowActions: (mangaIds) =>
                      _refreshMangas(mangaIds, freshWins: true),
                  isSelectedFor: (chapter) =>
                      widget.selectedChapters.value.containsKey(chapter.id),
                  canTapSelect: widget.selectedChapters.value.isNotEmpty,
                  toggleSelect: (val) => _toggleSelect(val),
                  selectedChapters: widget.selectedChapters,
                  selectionAnchor: widget.selectionAnchor,
                  orderedChapters: items,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wrapWithDateHeader(
    BuildContext context,
    List<ChapterWithMangaDto> items,
    int flatIndex,
    Widget tile,
    Set<int> headerIndices,
  ) {
    final desktop = context.usesDesktopShell;
    Widget wrap(Widget child) => desktop ? _updatesColumn(child) : child;
    if (!headerIndices.contains(flatIndex)) return wrap(tile);
    final currentDate = int.tryParse(items[flatIndex].fetchedAt);
    return wrap(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(currentDate.toDaysAgoFromSeconds(context))),
          tile,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PagingListener(
      controller: widget.controller,
      builder: (context, state, fetchNextPage) => PagedSliverList(
        state: state,
        fetchNextPage: fetchNextPage,
        builderDelegate: PagedChildBuilderDelegate<ChapterWithMangaDto>(
          firstPageProgressIndicatorBuilder: (context) =>
              const CenterSorayomiShimmerIndicator(),
          firstPageErrorIndicatorBuilder: (context) => Emoticons(
            title: state.error.toString(),
            button: TextButton(
              onPressed: widget.resetList,
              child: Text(context.l10n.retry),
            ),
          ),
          noItemsFoundIndicatorBuilder: (context) => Emoticons(
            title: context.l10n.noUpdatesFound,
            button: TextButton(
              onPressed: widget.resetList,
              child: Text(context.l10n.refresh),
            ),
          ),
          itemBuilder: (context, _, index) => _buildItem(context, state, index),
        ),
      ),
    );
  }
}


/// Hold the autoDispose provider during refresh so an unobserved request cannot tear down mid-fetch.
Future<ChapterDto?> refetchChapter(WidgetRef ref, int chapterId) async {
  final provider = chapterProvider(chapterId: chapterId);
  final keepAlive = ref.listenManual(provider, (_, _) {});
  try {
    return await ref.refresh(provider.future);
  } finally {
    keepAlive.close();
  }
}

/// Stops before the first known ID; boundaryFound lets callers stop fetching older pages.
({List<ChapterWithMangaDto> items, bool boundaryFound})
extractNewUpdatesFromPage(
  List<ChapterWithMangaDto> nodes,
  Set<int> existingIds,
) {
  final knownIndex = nodes.indexWhere((c) => existingIds.contains(c.id));
  if (knownIndex >= 0) {
    return (items: nodes.take(knownIndex).toList(), boundaryFound: true);
  }
  return (items: nodes.toList(), boundaryFound: false);
}

class UpdatesScreen extends HookConsumerWidget {
  const UpdatesScreen({super.key});

  // Drop replies after a refresh/filter reset so results from different lists cannot interleave.
  Future<ServerPage<ChapterWithMangaDto>> _fetchPage(
    UpdatesRepository repository,
    int pageKey,
    UpdatesFilter filter,
  ) async {
    final page = await repository.getRecentChaptersPage(
      pageNo: pageKey,
      filter: filter,
    );
    if (page == null) {
      return (items: <ChapterWithMangaDto>[], hasNextPage: false);
    }
    return (items: page.nodes, hasNextPage: page.hasNextPage);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the screen context after awaits; row contexts can be recycled during scroll.
    final screenContext = context;
    final updatesRepository = ref.watch(updatesRepositoryProvider);
    final lastUpdated = ref.watch(libraryLastUpdatedProvider).value;
    final selectedChapters = useState<Map<int, ChapterDto>>({});
    final selectionAnchor = useState<int?>(null);
    final filter = ref.watch(updatesFilterProvider);
    final hasActiveFilters = ref.watch(updatesHasActiveFiltersProvider);
    final groupingMode =
        ref.watch(updatesGroupingModeProvider) ?? UpdatesGroupingMode.collapsed;
    final displayMode =
        ref.watch(updatesDisplayModeProvider) ?? UpdatesDisplayMode.grid;
    final gridWidth =
        ref.watch(gridMinWidthProvider) ??
        DBKeys.gridMangaCoverWidth.initial as double;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final fixedColumns =
        (isLandscape
            ? ref.watch(libraryLandscapeColumnsProvider)
            : ref.watch(libraryPortraitColumnsProvider)) ??
        0;
    final phone = context.windowSizeClass == WindowSizeClass.compact;
    final persistentBox =
        phone && ref.watch(libraryPersistentSearchBarProvider).ifNull();
    // The fetcher is captured once; read current filters through a holder to avoid stale closures.
    final latestFilter = useRef(filter);
    latestFilter.value = filter;
    final controller = useServerPagingController<ChapterWithMangaDto>(
      firstPageKey: 0,
      // Read the repository per request because endpoint switches dispose the captured client.
      fetchPage: (pageKey) => _fetchPage(
        ref.read(updatesRepositoryProvider),
        pageKey,
        latestFilter.value,
      ),
    );
    // List resets invalidate replies from earlier generations.
    final generation = useRef(0);
    final resetList = useCallback(() {
      generation.value++;
      selectedChapters.value = ({});
      selectionAnchor.value = null;
      controller.refresh();
    }, []);
    // Custom covers arrive through meta the cached rows were fetched without.
    final coverRevision = ref.watch(customCoverRevisionProvider);
    final isCoverRevisionMount = useRef(true);
    useEffect(() {
      if (isCoverRevisionMount.value) {
        isCoverRevisionMount.value = false;
        return null;
      }
      resetList();
      return null;
    }, [coverRevision]);
    // Use the running-only socket to detect completion; prepend new rows without losing scroll position.
    final lastRunningUpdates = useRef<bool>(false);
    Future<void> liveUpdate() async {
      final gen = generation.value;
      final existingIds = {
        for (final item in controller.items ?? <ChapterWithMangaDto>[]) item.id,
      };
      final newItems = <ChapterWithMangaDto>[];
      // Cap at three pages; larger backlogs reset instead of prepending many stale entries.
      const maxPages = 3;
      for (var pageNo = 0; pageNo < maxPages; pageNo++) {
        final snapshot = await AsyncValue.guard(
          () => updatesRepository.getRecentChaptersPage(
            pageNo: pageNo,
            filter: latestFilter.value,
          ),
        );
        if (generation.value != gen) return;
        final page = snapshot.asData?.value;
        if (page == null) return;
        final result = extractNewUpdatesFromPage(page.nodes, existingIds);
        newItems.addAll(result.items);
        if (result.boundaryFound) break;
        if (!page.hasNextPage) break;
        if (pageNo == maxPages - 1) {
          resetList();
          return;
        }
      }
      if (newItems.isEmpty || !screenContext.mounted) return;
      // Prepend within the first page to preserve page keys and the next fetch key.
      final pages = controller.pages;
      if (pages == null || pages.isEmpty) return;
      controller.value = controller.value.copyWith(
        pages: [
          [...newItems, ...pages.first],
          ...pages.skip(1),
        ],
      );
    }

    ref.listen(updateRunningSocketProvider, (_, next) {
      final running = next.value;
      if (running == null) return;
      if (lastRunningUpdates.value && !running) {
        liveUpdate();
      }
      lastRunningUpdates.value = running;
    });
    // Skip the mount run to avoid fetching page zero twice; later server-side filter changes reset all pages.
    final isFilterMount = useRef(true);
    useEffect(() {
      if (isFilterMount.value) {
        isFilterMount.value = false;
        return null;
      }
      resetList();
      return null;
    }, [filter]);
    final selecting = selectedChapters.value.isNotEmpty;
    final desktop = context.usesDesktopShell;
    final desktopGrid = desktop && displayMode == UpdatesDisplayMode.grid;
    final topBar = showsMergedTopBar(context);
    final pageScope = useMemoized(FocusScopeNode.new);
    useEffect(() => pageScope.dispose, [pageScope]);
    final wasSelecting = usePrevious(selecting);
    useEffect(() {
      if (!desktop) return null;
      if (selecting && wasSelecting != true) pageScope.requestFocus();
      if (!selecting && wasSelecting == true) selectionAnchor.value = null;
      return null;
    }, [selecting]);
    void clearSelection() {
      selectedChapters.value = ({});
      selectionAnchor.value = null;
    }

    final closeSelection = IconButton(
      onPressed: clearSelection,
      icon: const Icon(FluentIcons.dismiss_24_regular),
    );
    final selectionTitle = Text(
      context.l10n.numSelected(selectedChapters.value.length),
    );
    final search = DesktopSearchField(
      query: ref.watch(unifiedSearchQueryProvider),
      onChanged: (value) =>
          ref.read(unifiedSearchQueryProvider.notifier).state = value,
      onNavigate: () =>
          ref.read(unifiedSearchQueryProvider.notifier).state = '',
    );
    final scheme = context.theme.colorScheme;
    final filterButtonKey = useMemoized(GlobalKey.new);
    final displayButtonKey = useMemoized(GlobalKey.new);
    final selectionMoreButtonKey = useMemoized(GlobalKey.new);
    final filterFocus = useMemoized(FocusNode.new);
    final displayFocus = useMemoized(FocusNode.new);
    useEffect(() {
      return () {
        filterFocus.dispose();
        displayFocus.dispose();
      };
    }, [filterFocus, displayFocus]);
    final filterBox = DesktopToolbarBox(
      key: filterButtonKey,
      borderColor: hasActiveFilters ? scheme.primary : null,
      child: InkWell(
        focusNode: filterFocus,
        onTap: () => showAnchoredPanel(
          context: context,
          buttonKey: filterButtonKey,
          focusNode: filterFocus,
          panelWidth: 400,
          child: const UpdatesFilterPanel(),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 6),
          child: Row(
            spacing: 8,
            children: [
              const Icon(FluentIcons.filter_24_regular, size: 20),
              Text(context.l10n.filter),
              const Icon(FluentIcons.caret_down_24_filled, size: 20),
            ],
          ),
        ),
      ),
    );
    final displayBox = DesktopToolbarBox(
      key: displayButtonKey,
      child: Tooltip(
        message: context.l10n.display,
        child: InkWell(
          focusNode: displayFocus,
          onTap: () => showAnchoredPanel(
            context: context,
            buttonKey: displayButtonKey,
            focusNode: displayFocus,
            panelWidth: 400,
            child: const UpdatesDisplayPanel(),
          ),
          child: const Padding(
            padding: EdgeInsets.only(left: 10, right: 6),
            child: Row(
              spacing: 2,
              children: [
                Icon(FluentIcons.grid_24_regular, size: 20),
                Icon(FluentIcons.caret_down_24_filled, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
    final updateState = updateStatusOf(
      ref.watch(updateProgressSocketProvider),
      context.l10n.update,
    );
    final updateBox = DesktopToolbarBox(
      borderColor: updateState.running ? scheme.primary : null,
      child: InkWell(
        onTap: () => toggleLibraryUpdate(ref, updateState.running),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            spacing: 8,
            children: [
              Icon(
                updateState.running
                    ? FluentIcons.stop_24_regular
                    : FluentIcons.arrow_clockwise_24_regular,
                size: 20,
              ),
              Text(updateState.label),
            ],
          ),
        ),
      ),
    );
    final upcomingBox = DesktopToolbarBox(
      child: InkWell(
        onTap: () => const UpcomingRoute().push(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            spacing: 8,
            children: [
              const Icon(FluentIcons.calendar_month_24_regular, size: 20),
              Text(context.l10n.upcoming),
            ],
          ),
        ),
      ),
    );
    final desktopActions = <Widget>[
      updateBox,
      upcomingBox,
      filterBox,
      displayBox,
      IconTheme.merge(
        data: const IconThemeData(size: 20),
        child: SyncYomiSyncButton(onSynced: resetList),
      ),
      IconTheme.merge(
        data: const IconThemeData(size: 20),
        child: const UpdateStatusPopupMenu(),
      ),
    ];
    final actions = <Widget>[
      if (phone && !persistentBox)
        const PhoneSearchEntry(origin: PhoneSearchOrigin.plain),
      if (desktop) ...desktopActions else ...[
        SyncYomiSyncButton(onSynced: resetList),
        IconButton(
          icon: const Icon(FluentIcons.filter_24_regular),
          tooltip: context.l10n.filter,
          color: hasActiveFilters ? scheme.primary : null,
          onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            shape: RoundedRectangleBorder(
              borderRadius: KBorderRadius.rT16.radius,
            ),
            clipBehavior: Clip.hardEdge,
            builder: (_) => const UpdatesFilterSheet(),
            sheetAnimationStyle: context.motionStyle,
          ),
        ),
        IconButton(
          icon: const Icon(FluentIcons.calendar_month_24_regular),
          tooltip: context.l10n.upcoming,
          onPressed: () => const UpcomingRoute().push(context),
        ),
        const UpdateStatusPopupMenu(),
      ],
    ];
    final selectionHeader = selecting && desktop
        ? ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final loadedChapters = controller.items ?? const <ChapterDto>[];
              return ChapterSelectionHeader(
                selected: selectedChapters.value.values.toList(),
                ordered: loadedChapters,
                bulk: loadedChapters,
                anchorId: selectionAnchor.value,
                desktop: true,
                seriesUrl: null,
                moreButtonKey: selectionMoreButtonKey,
                onClear: clearSelection,
                onSelectAll: () => selectedChapters.value = {
                  for (final c in loadedChapters) c.id: c,
                },
                loadSeriesChapters: (mangaId) =>
                    loadSeriesChapters(ref, mangaId),
                refresh: (online) async => resetList(),
                onSelect: (next, anchorId) {
                  selectedChapters.value = next;
                  selectionAnchor.value = anchorId;
                },
              );
            },
          )
        : null;
    final scaffold = Scaffold(
      floatingActionButton: selecting || desktop
          ? null
          : const UpdateStatusFab(),
      appBar: selecting && !desktop
          ? (topBar
                ? null
                : AppBar(leading: closeSelection, title: selectionTitle))
          : topBar
          ? null
          : AppBar(
              title: context.usesDesktopShell
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: search,
                      ),
                    )
                  : Text(context.l10n.updates),
              bottom: persistentBox
                  ? const PhoneSearchBoxBottom(origin: PhoneSearchOrigin.plain)
                  : null,
              actions: actions,
            ),
      bottomSheet: selecting && !desktop
          ? MultiChaptersActionsBottomAppBar(
              selectedChapters: selectedChapters,
              afterOptionSelected: () async => resetList(),
            )
          : null,
      body: Column(
        children: [
          if (selectionHeader != null) _updatesColumn(selectionHeader),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => resetList(),
              child: CustomScrollView(
                slivers: [
                  if (lastUpdated != null &&
                      !(desktop && selecting) &&
                      (int.tryParse(lastUpdated) ?? 0) > 0)
                    SliverToBoxAdapter(
                      child: desktop && !desktopGrid
                          ? _updatesColumn(
                              _lastUpdatedLine(context, lastUpdated),
                            )
                          : _lastUpdatedLine(context, lastUpdated),
                    ),
                  _UpdatesPagedList(
                    controller: controller,
                    groupingMode: groupingMode,
                    displayMode: displayMode,
                    gridWidth: gridWidth,
                    fixedColumns: fixedColumns,
                    selectedChapters: selectedChapters,
                    selectionAnchor: selectionAnchor,
                    getGeneration: () => generation.value,
                    screenContext: screenContext,
                    resetList: resetList,
                    refetchChapter: (id) => refetchChapter(ref, id),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    Widget content = scaffold;
    if (desktop) {
      content = FocusScope(
        node: pageScope,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape &&
              selecting) {
            clearSelection();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: content,
      );
    }
    if (!topBar) return content;
    if (selecting && !desktop) {
      return TopBarSlot(
        slotKey: 'selection',
        content: DesktopTitleSlot(
          leading: closeSelection,
          title: selectionTitle,
        ),
        minWidth: titleTopBarSlotMinWidth(0),
        child: content,
      );
    }
    return TopBarSlot(
      content: desktopToolbarRow(search: search, actions: desktopActions),
      minWidth: updatesTopBarSlotMinWidth(
        context,
        updateLabel: updateState.label,
        upcomingLabel: context.l10n.upcoming,
        filterLabel: context.l10n.filter,
      ),
      child: content,
    );
  }
}
