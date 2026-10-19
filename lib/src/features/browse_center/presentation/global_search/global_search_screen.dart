// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../constants/enum.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/search_field.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../source/controller/source_controller.dart';
import 'controller/source_quick_search_controller.dart';
import 'widgets/source_short_search.dart';

String _normalizedTitle(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Null until every source has settled; otherwise the titles matching [query]
/// exactly across the settled results.
List<MangaDto>? _exactMatches(
  AsyncValue<List<QuickSearchResults>> results,
  String query,
) {
  final rows = results.value;
  if (rows == null || results.isLoading || results.isRefreshing) return null;
  if (rows.any((e) => e.mangaList.isLoading)) return null;
  final want = _normalizedTitle(query);
  return [
    for (final row in rows)
      for (final manga in row.mangaList.value ?? const <MangaDto>[])
        if (_normalizedTitle(manga.title) == want) manga,
  ];
}

class GlobalSearchScreen extends HookConsumerWidget {
  const GlobalSearchScreen({
    super.key,
    this.initialQuery,
    this.fromSuggestion = false,
  });
  final String? initialQuery;

  /// Opened from a Suggestions card: a lone exact title match opens straight
  /// into that series.
  final bool fromSuggestion;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState(initialQuery);
    final queryController = useTextEditingController(text: initialQuery);
    final searchFocusNode = useFocusNode();
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
          searchFocusNode.requestFocus();
        }
      });
      return null;
    }, const []);
    final quickSearchResult = ref.watch(
      quickSearchResultsProvider(query: query.value),
    );
    final sourceList = ref.watch(sourceListProvider);
    final onlyHasResults = ref.watch(globalSearchOnlyHasResultsProvider);
    final hasPinned = ref.watch(pinnedSourcesProvider).isNotEmpty;
    final decided = useRef(false);
    final cancelled = useRef(false);
    // Latest focus state, tracked from the node itself: a build-time read
    // races an unfocus that lands without rebuilding the page.
    final hadFocus = useRef(false);
    useEffect(() {
      void update() => hadFocus.value = searchFocusNode.hasFocus;
      update();
      searchFocusNode.addListener(update);
      return () => searchFocusNode.removeListener(update);
    }, [searchFocusNode]);
    final wasTopBar = useRef(false);

    void cancelAutoOpen() => cancelled.value = true;

    useEffect(() {
      bool onKey(KeyEvent event) {
        if (event is KeyDownEvent &&
            ModalRoute.of(context)?.isCurrent == true) {
          cancelAutoOpen();
        }
        return false;
      }

      HardwareKeyboard.instance.addHandler(onKey);
      return () => HardwareKeyboard.instance.removeHandler(onKey);
    }, const []);

    // A refreshing source list can still settle into extra sources; deciding
    // against it would miss a second exact match.
    final sourcesSettled = !sourceList.isLoading && !sourceList.isRefreshing;
    if (fromSuggestion &&
        sourcesSettled &&
        !decided.value &&
        !cancelled.value &&
        query.value == initialQuery &&
        initialQuery.isNotBlank) {
      final matches = _exactMatches(quickSearchResult, initialQuery!);
      if (matches != null) {
        decided.value = true;
        if (matches.length == 1) {
          final mangaId = matches.single.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Never replace a route the user opened on top meanwhile.
            if (!context.mounted ||
                cancelled.value ||
                query.value != initialQuery ||
                ModalRoute.of(context)?.isCurrent != true) {
              return;
            }
            MangaRoute(mangaId: mangaId).pushReplacement(context);
          });
        }
      }
    }
    final results = Expanded(
      child: quickSearchResult.showUiWhenData(context, (data) {
        if (data.isBlank) {
          return Emoticons(
            title: context.l10n.noSourcesFound,
            button: TextButton(
              onPressed: () => ref.invalidate(sourceListProvider),
              child: Text(context.l10n.refresh),
            ),
          );
        }
        // "Has results" hides sources still loading / that returned none.
        final visible = onlyHasResults
            ? data
                  .where((e) => (e.mangaList.value?.isNotEmpty).ifNull())
                  .toList()
            : data;
        return ListView.builder(
          itemBuilder: (context, index) => SourceShortSearch(
            source: visible[index].source,
            mangaList: visible[index].mangaList,
            query: query.value,
          ),
          itemCount: visible.length,
        );
      }),
    );
    final chips = _SearchFilterChips(
      hasPinned: hasPinned,
      onInteract: cancelAutoOpen,
    );
    // Native desktop draws the search box in the shell bar instead of an
    // app bar; the filter chips stay in the page body. The focus node and
    // controller are shared so the draft survives the move, and the slot
    // mount autofocuses only when focus was held across the toggle: the
    // slot mounts a frame after the old field detaches, so bare refocusing
    // would be lost — and unconditional autofocus would steal focus back
    // after an explicit unfocus.
    final topBar = useDesktopTopBar(context);
    final restoreFocus = topBar && !wasTopBar.value && hadFocus.value;
    wasTopBar.value = topBar;
    final searchField = SearchField(
      controller: queryController,
      focusNode: searchFocusNode,
      autofocus: restoreFocus,
      onChanged: (_) => cancelAutoOpen(),
      onSubmitted: (value) {
        cancelAutoOpen();
        query.value = value;
      },
    );
    final searchTitleBox = Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: searchField,
      ),
    );
    final content = Listener(
      onPointerDown: (_) => cancelAutoOpen(),
      onPointerSignal: (_) => cancelAutoOpen(),
      child: NotificationListener<UserScrollNotification>(
        onNotification: (_) {
          cancelAutoOpen();
          return false;
        },
        child: Scaffold(
          appBar: context.isDesktop
              ? null
              : AppBar(
                  leading: detailNavigationBackButton(context),
                  title: Text(context.l10n.globalSearch),
                  bottom: PreferredSize(
                    preferredSize: kCalculateAppBarBottomSize([true]),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: context.isLargeTablet
                                ? context.widthScale(scale: .5)
                                : null,
                            child: Padding(
                              padding: KEdgeInsets.h16v4.size,
                              child: searchField,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          body: context.isDesktop
              ? SafeArea(
                  child: Column(
                    children: [
                      topBar
                          ? Semantics(
                              header: true,
                              namesRoute: true,
                              label: context.l10n.globalSearch,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: chips,
                              ),
                            )
                          : Semantics(
                              header: true,
                              namesRoute: true,
                              label: context.l10n.globalSearch,
                              child: _DesktopHeader(
                                hasPinned: hasPinned,
                                chips: chips,
                                searchField: searchField,
                              ),
                            ),
                      results,
                    ],
                  ),
                )
              : Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: chips,
                    ),
                    results,
                  ],
                ),
        ),
      ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: searchTitleBox,
      minWidth: searchTopBarSlotMinWidth(0),
      child: content,
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({
    required this.hasPinned,
    required this.chips,
    required this.searchField,
  });
  final bool hasPinned;
  final Widget chips;
  final Widget searchField;

  @override
  Widget build(BuildContext context) {
    final backButton = detailNavigationBackButton(context);
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (backButton != null) ...[backButton, const SizedBox(width: 20)],
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: searchField,
              ),
            ),
            const SizedBox(width: 28),
            chips,
          ],
        ),
      ),
    );
  }
}

class _SearchFilterChips extends ConsumerWidget {
  const _SearchFilterChips({required this.hasPinned, required this.onInteract});
  final bool hasPinned;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(globalSearchScopeProvider);
    final onlyHasResults = ref.watch(globalSearchOnlyHasResultsProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasPinned) ...[
          FilterChip(
            showCheckmark: false,
            avatar: const Icon(Icons.push_pin_outlined, size: 18),
            label: Text(context.l10n.pinnedSources),
            selected: scope == GlobalSearchSourceFilter.pinned,
            onSelected: (_) {
              onInteract();
              ref
                  .read(globalSearchScopeProvider.notifier)
                  .update(GlobalSearchSourceFilter.pinned);
            },
          ),
          const SizedBox(width: 8),
        ],
        FilterChip(
          showCheckmark: false,
          avatar: const Icon(Icons.done_all_rounded, size: 18),
          label: Text(context.l10n.all),
          selected: !hasPinned || scope == GlobalSearchSourceFilter.all,
          onSelected: (_) {
            onInteract();
            ref
                .read(globalSearchScopeProvider.notifier)
                .update(GlobalSearchSourceFilter.all);
          },
        ),
        const SizedBox(width: 12),
        FilterChip(
          showCheckmark: false,
          avatar: const Icon(Icons.filter_list_rounded, size: 18),
          label: Text(context.l10n.hasResults),
          selected: onlyHasResults,
          onSelected: (_) {
            onInteract();
            ref.read(globalSearchOnlyHasResultsProvider.notifier).state =
                !onlyHasResults;
          },
        ),
      ],
    );
  }
}
