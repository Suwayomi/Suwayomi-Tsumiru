// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../constants/endpoints.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/hooks/paging_controller_hook.dart';
import '../../../../utils/launch_url_in_web.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../utils/webui_meta/webui_settings.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/search_field.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../data/source_repository/source_repository.dart';
import '../../domain/filter/filter_model.dart';
import '../../domain/source/source_model.dart';
import 'controller/source_manga_controller.dart';
import 'source_page_sequence.dart';
import 'widgets/source_manga_display_icon_popup.dart';
import 'widgets/source_manga_display_view.dart';
import 'widgets/source_manga_filter.dart';
import 'widgets/source_type_selectable_chip.dart';

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
    final showSearch = useState(initialQuery.isNotBlank);
    final sourcePages = useMemoized(() => SourcePageSequence<MangaDto>());
    final controller = useServerPagingController<MangaDto>(
      firstPageKey: 1,
      // Read per request: a LAN/remote endpoint switch replaces the client,
      // and the one captured on the first build is disposed with it.
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

    useEffect(() {
      refresh();
      return null;
    }, [hideLibraryEntries]);
    return source.showUiWhenData(
      context,
      (data) {
        // Native desktop draws the title and actions in the shell bar
        // instead of an app bar; the type chips and search box stay in the
        // page body.
        final topBar = showsMergedTopBar(context);
        final title = Text(data?.displayName ?? context.l10n.source);
        final actions = <Widget>[
          IconButton(
            onPressed: () => showSearch.value = true,
            icon: const Icon(Icons.search_rounded),
          ),
          const SourceMangaDisplayIconPopup(),
          if (data?.homeUrl.isNotBlank ?? false)
            PopupMenuButton<void>(
              itemBuilder: (_) => [
                PopupMenuItem<void>(
                  onTap: () {
                    final api = Endpoints.baseApi(
                      baseUrl: ref.read(serverUrlProvider),
                      port: ref.read(serverPortProvider),
                      addPort: ref.read(serverPortToggleProvider).ifNull(),
                    );
                    launchUrlInWeb(
                      context,
                      '${api.endsWith('/') ? api : '$api/'}webview#${data!.homeUrl}',
                      ref.read(toastProvider),
                    );
                  },
                  child: Text(context.l10n.openHomepage),
                ),
              ],
            ),
          if ((data?.isConfigurable).ifNull())
            IconButton(
              onPressed: () => SourcePreferenceRoute(
                sourceId: sourceId,
              ).go(context),
              icon: const Icon(Icons.settings_rounded),
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
                      onClose: () => showSearch.value = (false),
                      onSubmitted: (val) {
                        if (sourceType == SourceType.SEARCH) {
                          query.value = (val);
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
        // Edge-drag would fight the system back gesture; the filter button is
        // the way in.
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
                      query: query.value,
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
                      icon: Icon(Icons.filter_alt_rounded),
                      onPressed: () => context.windowSizeClass >=
                              WindowSizeClass.medium
                          ? Scaffold.of(context).openEndDrawer()
                          : showModalBottomSheet(
                              context: context,
                              builder: (context) => SourceMangaFilter(
                              filters: filterList.toList(),
                                sourceId: sourceId,
                                appliedChanges: appliedFilter,
                              query: query.value,
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
