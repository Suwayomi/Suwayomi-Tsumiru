// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../constants/db_keys.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/hooks/paging_controller_hook.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../utils/webui_meta/webui_settings.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/desktop/desktop_view_switch.dart';
import '../../../../widgets/search_field.dart';
import '../../../../widgets/server_image.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../library/presentation/library/widgets/desktop_library_panels.dart';
import '../../../library/presentation/library/widgets/desktop_library_toolbar.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../data/source_repository/source_repository.dart';
import '../../domain/filter/filter_model.dart';
import '../../domain/source/source_model.dart';
import '../source/controller/source_controller.dart';
import '../source/widgets/source_context_menu.dart';
import 'controller/source_manga_controller.dart';
import 'source_page_sequence.dart';
import 'widgets/desktop_source_display_panel.dart';
import 'widgets/desktop_source_filter_panel.dart';
import 'widgets/desktop_source_search_box.dart';
import 'widgets/source_manga_display_icon_popup.dart';
import 'widgets/source_manga_display_view.dart';
import 'widgets/source_manga_filter.dart';
import 'widgets/source_switcher_menu.dart';
import 'widgets/source_type_selectable_chip.dart';

const double _sourceSwitcherNameMaxWidth = 220;
const double _sourceSwitcherNameMinWidth = 120;
const _sourceSwitcherBaseWidth = 16.0 + 28.0 + 8.0 + 4.0 + 20.0;

// Compact controls first so the search retains its preferred width.
bool _sourceCatalogueIsCompact(
  BuildContext context,
  BoxConstraints constraints, {
  required String filterLabel,
  required double leadingWidth,
  required int actionCount,
}) {
  if (!constraints.hasBoundedWidth) return false;
  final labelWidth = measureToolbarLabelWidth(context, filterLabel);
  final neededBesidesSearch =
      2 * kDesktopToolbarSlotHPadding +
      (1 + actionCount) * kDesktopTopBarGap +
      leadingWidth +
      (kToolbarFilterFullChrome + labelWidth + kToolbarBoxBorderWidth) +
      (kToolbarDisplayBoxWidth + kToolbarBoxBorderWidth) +
      (actionCount - 2) * 48.0;
  return constraints.maxWidth - neededBesidesSearch < kDesktopSearchMaxWidth;
}

// Shrink the switcher first so the search retains its preferred width.
double _sourceSwitcherNameWidth(
  double maxWidth, {
  required double backWidth,
  required int actionCount,
}) {
  final fixedBesidesSearch =
      2 * kDesktopToolbarSlotHPadding +
      (1 + actionCount) * kDesktopTopBarGap +
      backWidth +
      _sourceSwitcherBaseWidth +
      (kToolbarFilterCompactWidth + kToolbarBoxBorderWidth) +
      (kToolbarDisplayBoxWidth + kToolbarBoxBorderWidth) +
      (actionCount - 2) * 48.0;
  return (maxWidth - fixedBesidesSearch - kDesktopSearchMaxWidth)
      .clamp(_sourceSwitcherNameMinWidth, _sourceSwitcherNameMaxWidth)
      .toDouble();
}

class SourceMangaListScreen extends HookConsumerWidget {
  const SourceMangaListScreen({
    super.key,
    required this.sourceId,
    required this.sourceType,
    this.initialQuery,
  });
  final String sourceId;
  final SourceType sourceType;
  final String? initialQuery;

  Future<ServerPage<MangaDto>> _fetchPage(
    SourceRepository repository,
    int pageKey, {
    String? query,
    List<FilterChange>? filter,
    bool hideLibraryEntries = false,
  }) async {
    final page = await repository.fetchSourceManga(
      sourceId: sourceId,
      sourceType: sourceType,
      page: pageKey,
      query: query,
      filters: filter,
    );
    if (page == null) return (items: <MangaDto>[], hasNextPage: false);
    final items = visibleSourceMangas(
      page.mangas,
      hideLibraryEntries: hideLibraryEntries,
    );
    return (items: items, hasNextPage: page.hasNextPage.ifNull());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideLibraryEntries = ref.watch(
      webUiBoolProvider('hideLibraryEntries'),
    );
    final appliedFilter = ref.watch(appliedSourceFilterProvider(sourceId));
    final appliedFilterNotifier =
        ref.watch(appliedSourceFilterProvider(sourceId).notifier);
    final liveAppliedFilter = useRef(appliedFilter);
    liveAppliedFilter.value = appliedFilter;
    final filterList =
        ref.watch(baseSourceMangaFilterListProvider(sourceId)).value;
    final source = ref.watch(sourceProvider(sourceId));

    final query = useState(initialQuery);
    final searchDraft = useRef(initialQuery);
    useEffect(() {
      searchDraft.value = query.value;
      return null;
    }, [query.value]);
    final showSearch = useState(initialQuery.isNotBlank);
    final sourcePages = useMemoized(() => SourcePageSequence<MangaDto>());
    final controller = useServerPagingController<MangaDto>(
      firstPageKey: 1,
      // Read per request because endpoint switches dispose the previous client.
      fetchPage: (pageKey) async {
        final repository = ref.read(sourceRepositoryProvider);
        final hideLibraryEntries = ref.read(
          webUiBoolProvider('hideLibraryEntries'),
        );
        final currentQuery = query.value;
        final currentFilter = liveAppliedFilter.value;
        return sourcePages.fetch(
        pageKey,
          (sourcePage) => _fetchPage(
            repository,
            sourcePage,
            hideLibraryEntries: hideLibraryEntries,
            query: currentQuery,
            filter: currentFilter,
      ),
    );
      },
    );
    void refresh() {
      sourcePages.refresh();
      controller.refresh();
    }

    final filterButtonKey = useMemoized(GlobalKey.new);
    final displayButtonKey = useMemoized(GlobalKey.new);
    final switcherButtonKey = useMemoized(GlobalKey.new);
    final filterFocus = useFocusNode();
    final displayFocus = useFocusNode();
    final searchFocus = useFocusNode();

    useEffect(() {
      // Providers cannot update during build; defer the recents write past the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref.read(sourceRecentIdsProvider.notifier).recordOpened(sourceId);
      });
      return null;
    }, [sourceId]);

    useEffect(() {
      refresh();
      return null;
    }, [hideLibraryEntries]);
    return source.showUiWhenData(
      context,
      (data) {
        final topBar = showsMergedTopBar(context);
        final title = Text(data?.displayName ?? context.l10n.source);
        final actions = <Widget>[
          IconButton(
            onPressed: () => showSearch.value = true,
            icon: const Icon(FluentIcons.search_24_regular),
          ),
          const SourceMangaDisplayIconPopup(),
          if (data?.homeUrl.isNotBlank ?? false)
            PopupMenuButton<void>(
              icon: const Icon(
                FluentIcons.more_vertical_24_regular,
              ),
              itemBuilder: (_) => [
                PopupMenuItem<void>(
                  onTap: () =>
                      openSourceHomepage(context, ref, data!.homeUrl),
                  child: Text(context.l10n.openHomepage),
                ),
              ],
            ),
          if ((data?.isConfigurable).ifNull())
            IconButton(
              onPressed: () => SourcePreferenceRoute(
                sourceId: sourceId,
              ).go(context),
              icon: const Icon(FluentIcons.settings_24_regular),
            ),
        ];
        final toolbarBottom = Column(
          children: [
            Row(
              children: [
                SourceTypeSelectableChip(
                  value: SourceType.POPULAR,
                  groupValue: sourceType,
                  onSelected: (val) {
                    if (sourceType == SourceType.POPULAR) return;
                    SourceTypeRoute(
                      sourceId: sourceId,
                      sourceType: SourceType.POPULAR,
                    ).go(context);
                  },
                ),
                if ((data?.supportsLatest).ifNull())
                  SourceTypeSelectableChip(
                    value: SourceType.LATEST,
                    groupValue: sourceType,
                    onSelected: (val) {
                      if (sourceType == SourceType.LATEST) return;
                      SourceTypeRoute(
                        sourceId: sourceId,
                        sourceType: SourceType.LATEST,
                      ).go(context);
                    },
                  ),
                Builder(
                  builder: (context) => SourceTypeSelectableChip(
                    value: SourceType.SEARCH,
                    groupValue: sourceType,
                    onSelected: (val) => SourceTypeRoute(
                      sourceId: sourceId,
                      sourceType: SourceType.SEARCH,
                    ).go(context),
                  ),
                ),
              ],
            ),
            const Divider(height: 0),
            if (showSearch.value)
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: context.windowSizeClass >= WindowSizeClass.expanded
                      ? context.widthScale(scale: .5)
                      : null,
                  child: Padding(
                    padding: KEdgeInsets.h16v4.size,
                    child: SearchField(
                      key: ValueKey(query.value),
                      initialText: query.value,
                      onChanged: (value) => searchDraft.value = value,
                      onClose: () => showSearch.value = (false),
                      onSubmitted: (val) {
                        if (sourceType == SourceType.SEARCH) {
                          query.value = val;
                          refresh();
                        } else {
                          if (val == null) return;
                          SourceTypeRoute(
                            sourceId: sourceId,
                            sourceType: SourceType.SEARCH,
                            query: val,
                          ).go(context);
                        }
                      },
                    ),
                  ),
                ),
              ),
          ],
        );
        final listBody = RefreshIndicator(
          onRefresh: () async => refresh(),
          child: SourceMangaDisplayView(
            sourceId: sourceId,
            sourceType: sourceType,
            controller: controller,
            source: data,
          ),
        );
        if (context.usesDesktopShell) {
          void submitSearch(String? val) {
            if (sourceType == SourceType.SEARCH) {
              query.value = val;
              refresh();
            } else {
              if (val == null) return;
              SourceTypeRoute(
                sourceId: sourceId,
                sourceType: SourceType.SEARCH,
                query: val,
              ).go(context);
            }
          }

          void openFilterPanel() {
            final filters = filterList;
            if (filters == null) return;
            showAnchoredPanel(
              context: context,
              buttonKey: filterButtonKey,
              focusNode: filterFocus,
              panelWidth: 720,
              panelHeight: 600,
              child: DesktopSourceFilterPanel(
                filters: filters.toList(),
                sourceId: sourceId,
                appliedChanges: appliedFilter,
                currentQuery: () => searchDraft.value,
                onSavedSearchSelected: (savedQuery, changes) {
                  appliedFilterNotifier.apply(changes);
                  if (sourceType == SourceType.SEARCH) {
                    query.value = savedQuery;
                    refresh();
                  } else {
                    SourceTypeRoute(
                      sourceId: sourceId,
                      sourceType: SourceType.SEARCH,
                      query: savedQuery,
                    ).go(context);
                  }
                },
                onReset: () {
                  appliedFilterNotifier.reset();
                  refresh();
                },
                onSubmitted: (value) {
                  appliedFilterNotifier.apply(value ?? const []);
                  if (sourceType == SourceType.SEARCH) {
                    refresh();
                  } else {
                    final draft = searchDraft.value;
                    SourceTypeRoute(
                      sourceId: sourceId,
                      sourceType: SourceType.SEARCH,
                      query: draft.isNotBlank ? draft : null,
                    ).go(context);
                  }
                },
              ),
            );
          }

          void openDisplayPanel() => showAnchoredPanel(
            context: context,
            buttonKey: displayButtonKey,
            focusNode: displayFocus,
            panelWidth: 320,
            child: const DesktopSourceDisplayPanel(),
          );

          void openWebView() {
            openSourceHomepage(context, ref, data?.homeUrl);
          }

          Widget switcherButton({
            double nameMaxWidth = _sourceSwitcherNameMaxWidth,
          }) => InkWell(
            key: switcherButtonKey,
            borderRadius: BorderRadius.circular(8),
            onTap: () => showSourceSwitcherMenu(
              context: context,
              ref: ref,
              buttonKey: switcherButtonKey,
              currentSourceId: sourceId,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ServerImage(
                      imageUrl: data?.iconUrl ?? '',
                      size: const Size.square(28),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Tooltip(
                      message: data?.displayName ?? context.l10n.source,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: nameMaxWidth,
                        ),
                        child: Text(
                          data?.displayName ?? context.l10n.source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(FluentIcons.chevron_down_24_regular, size: 20),
                ],
              ),
            ),
          );

          Widget catalogueSearchBox() => ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kDesktopSearchMaxWidth),
            child: CatalogueSearchBox(
              key: ValueKey(query.value),
              initialText: query.value,
              hintText: context.l10n.searchSourceHint(
                data?.displayName ?? context.l10n.source,
              ),
              focusNode: searchFocus,
              autofocus:
                  sourceType == SourceType.SEARCH && query.value.isBlank,
              onChanged: (value) => searchDraft.value = value,
              onSubmitted: submitSearch,
              onCleared: () {
                if (sourceType == SourceType.SEARCH) {
                  Navigator.of(context).maybePop();
                }
              },
            ),
          );

          List<Widget> desktopActions({bool compact = false}) {
            final scheme = context.theme.colorScheme;
            final hasFilters = filterList != null;
            final displayMode =
                ref.watch(sourceDisplayModeProvider) ??
                DBKeys.sourceDisplayMode.initial;
            final filterBox = DesktopToolbarBox(
              key: filterButtonKey,
              borderColor: appliedFilter.isNotEmpty ? scheme.primary : null,
              child: InkWell(
                focusNode: filterFocus,
                onTap: hasFilters ? openFilterPanel : null,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 6),
                  child: Row(
                    spacing: 8,
                    children: [
                      const Icon(FluentIcons.filter_24_regular, size: 20),
                      if (!compact) Text(context.l10n.filter),
                      const Icon(
                        FluentIcons.caret_down_24_filled,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            );
            return [
              Opacity(
                opacity: hasFilters ? 1 : 0.38,
                child: compact
                    ? Tooltip(
                        message: context.l10n.filter,
                        child: filterBox,
                      )
                    : filterBox,
              ),
              DesktopToolbarBox(
                key: displayButtonKey,
                child: Tooltip(
                  message: context.l10n.display,
                  child: InkWell(
                    focusNode: displayFocus,
                    onTap: openDisplayPanel,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10, right: 6),
                      child: Row(
                        spacing: 2,
                        children: [
                          Icon(displayMode?.icon, size: 20),
                          const Icon(
                            FluentIcons.caret_down_24_filled,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (data?.homeUrl.isNotBlank ?? false)
                IconButton(
                  tooltip: context.l10n.openHomepage,
                  onPressed: openWebView,
                  icon: const Icon(FluentIcons.globe_24_regular),
                ),
              if ((data?.isConfigurable).ifNull())
                IconButton(
                  tooltip: context.l10n.settings,
                  onPressed: () =>
                      SourcePreferenceRoute(sourceId: sourceId).go(context),
                  icon: const Icon(FluentIcons.settings_24_regular),
                ),
            ];
          }

          Widget desktopViewSwitch() {
            final types = [
              SourceType.POPULAR,
              if ((data?.supportsLatest).ifNull()) SourceType.LATEST,
              SourceType.SEARCH,
            ];
            String label(SourceType type) => switch (type) {
              SourceType.POPULAR => context.l10n.sourceTypePopular,
              SourceType.LATEST => context.l10n.sourceTypeLatest,
              SourceType.SEARCH => context.l10n.searchResults,
              SourceType.$unknown => '',
            };
            var selected = types.indexOf(sourceType);
            if (selected < 0) selected = 0;
            return DesktopViewSwitchBar(
              labels: [for (final type in types) label(type)],
              selectedIndex: selected,
              onChanged: (index) {
                final next = types[index];
                if (next == SourceType.SEARCH) {
                  final draft = searchDraft.value ?? query.value;
                  if (draft.isBlank) {
                    if (next != sourceType) {
                      SourceTypeRoute(
                        sourceId: sourceId,
                        sourceType: next,
                      ).go(context);
                    }
                    searchFocus.requestFocus();
                    return;
                  }
                  submitSearch(draft);
                  return;
                }
                if (next == sourceType) return;
                SourceTypeRoute(
                  sourceId: sourceId,
                  sourceType: next,
                ).go(context);
              },
            );
          }

          final desktopScaffold = Scaffold(
            body: Column(
              children: [
                desktopViewSwitch(),
                Expanded(child: listBody),
              ],
            ),
          );
          final backButton = detailNavigationBackButton(context);
          final backWidth = backButton != null ? 48.0 : 0.0;
          final iconCount =
              ((data?.homeUrl.isNotBlank ?? false) ? 1 : 0) +
              ((data?.isConfigurable).ifNull() ? 1 : 0);
          final slotActionCount = 2 + iconCount;
          final switcherWidth =
              _sourceSwitcherBaseWidth + _sourceSwitcherNameMaxWidth;
          final leadingWidth = backWidth + switcherWidth;
          return TopBarSlot(
            content: LayoutBuilder(
              builder: (context, constraints) {
                final compact = _sourceCatalogueIsCompact(
                  context,
                  constraints,
                  filterLabel: context.l10n.filter,
                  leadingWidth: leadingWidth,
                  actionCount: slotActionCount,
                );
                final nameWidth = compact
                    ? _sourceSwitcherNameWidth(
                        constraints.maxWidth,
                        backWidth: backWidth,
                        actionCount: slotActionCount,
                      )
                    : _sourceSwitcherNameMaxWidth;
                return desktopToolbarRow(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ?backButton,
                      switcherButton(nameMaxWidth: nameWidth),
                    ],
                  ),
                  search: catalogueSearchBox(),
                  actions: desktopActions(compact: compact),
                );
              },
            ),
            minWidth: searchTopBarSlotMinWidth(
              slotActionCount,
              leadingWidth,
            ),
            child: desktopScaffold,
          );
        }
        final scaffold = Scaffold(
          appBar: topBar
              ? null
              : AppBar(
                  title: title,
                  actions: actions,
                  bottom: PreferredSize(
                    preferredSize: kCalculateAppBarBottomSize([
                      true,
                      showSearch.value,
                    ]),
                    child: toolbarBottom,
                  ),
                ),
        // Edge-drag conflicts with the system back gesture.
        endDrawerEnableOpenDragGesture: false,
          endDrawer: filterList != null
            ? Drawer(
                width: kDrawerWidth,
                shape: const RoundedRectangleBorder(),
                child: Builder(
                  builder: (context) => SourceMangaFilter(
                      filters: filterList.toList(),
                    sourceId: sourceId,
                    appliedChanges: appliedFilter,
                      currentQuery: () => searchDraft.value,
                      onSavedSearchSelected: (savedQuery, changes) {
                        Navigator.pop(context);
                        appliedFilterNotifier.apply(changes);
                        if (sourceType == SourceType.SEARCH) {
                          query.value = savedQuery;
                          showSearch.value = savedQuery.isNotBlank;
                          refresh();
                        } else {
                          SourceTypeRoute(
                            sourceId: sourceId,
                            sourceType: SourceType.SEARCH,
                            query: savedQuery,
                          ).go(context);
                        }
                      },
                    onReset: () {
                      appliedFilterNotifier.reset();
                        refresh();
                    },
                    onSubmitted: (value) {
                      Navigator.pop(context);
                      appliedFilterNotifier.apply(value ?? const []);
                        refresh();
                    },
                  ),
                ),
              )
            : null,
        body: topBar
            ? Column(
                children: [
                  toolbarBottom,
                  Expanded(child: listBody),
                ],
              )
            : listBody,
        floatingActionButton:
              sourceType == SourceType.SEARCH && filterList != null
                ? Builder(
                    builder: (context) => FloatingActionButton.extended(
                      icon: Icon(FluentIcons.filter_24_regular),
                      onPressed: () => context.windowSizeClass >=
                              WindowSizeClass.medium
                          ? Scaffold.of(context).openEndDrawer()
                          : showModalBottomSheet(
                              context: context,
                              builder: (context) => SourceMangaFilter(
                              filters: filterList.toList(),
                                sourceId: sourceId,
                                appliedChanges: appliedFilter,
                              currentQuery: () => searchDraft.value,
                              onSavedSearchSelected: (savedQuery, changes) {
                                Navigator.pop(context);
                                appliedFilterNotifier.apply(changes);
                                if (sourceType == SourceType.SEARCH) {
                                  query.value = savedQuery;
                                  showSearch.value = savedQuery.isNotBlank;
                                  refresh();
                                } else {
                                  SourceTypeRoute(
                                    sourceId: sourceId,
                                    sourceType: SourceType.SEARCH,
                                    query: savedQuery,
                                  ).go(context);
                                }
                              },
                                onReset: () {
                                  appliedFilterNotifier.reset();
                                refresh();
                                },
                                onSubmitted: (value) {
                                  Navigator.pop(context);
                                  appliedFilterNotifier
                                      .apply(value ?? const []);
                                refresh();
                                },
                              ),
                              sheetAnimationStyle: context.motionStyle,
                            ),
                      label: Text(context.l10n.filter),
                    ),
                  )
                : null,
      );
        return titleTopBarSlot(
          topBar: topBar,
          leading: detailNavigationBackButton(context),
          title: title,
          actions: actions,
          child: scaffold,
        );
      },
      refresh: () => ref.refresh(sourceProvider(sourceId)),
      wrapper: (body) {
        final topBar = showsMergedTopBar(context);
        final title = Text(context.l10n.source);
        final scaffold = Scaffold(
          appBar: topBar ? null : AppBar(title: title),
          body: body,
        );
        return titleTopBarSlot(
          topBar: topBar,
          leading: detailNavigationBackButton(context),
          title: title,
          child: scaffold,
        );
      },
    );
  }
}
