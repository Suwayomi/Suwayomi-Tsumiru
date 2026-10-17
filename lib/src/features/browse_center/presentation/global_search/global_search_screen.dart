// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../constants/enum.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
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
  if (rows == null || results.isLoading) return null;
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
    final quickSearchResult = ref.watch(
      quickSearchResultsProvider(query: query.value),
    );
    final onlyHasResults = ref.watch(globalSearchOnlyHasResultsProvider);
    final hasPinned = ref.watch(pinnedSourcesProvider).isNotEmpty;
    final decided = useRef(false);
    final queryChanged = useRef(false);
    final tapped = useRef(false);
    if (query.value != initialQuery) queryChanged.value = true;
    if (fromSuggestion &&
        !decided.value &&
        !queryChanged.value &&
        !tapped.value &&
        initialQuery.isNotBlank) {
      final matches = _exactMatches(quickSearchResult, initialQuery!);
      if (matches != null) {
        decided.value = true;
        if (matches.length == 1) {
          final mangaId = matches.single.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
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
    final chips = _SearchFilterChips(hasPinned: hasPinned);
    return Listener(
      onPointerDown: (_) => tapped.value = true,
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
                            child: SearchField(
                              initialText: query.value,
                              onSubmitted: (value) => query.value = value,
                            ),
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
                    _DesktopHeader(
                      query: query,
                      hasPinned: hasPinned,
                      chips: chips,
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
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({
    required this.query,
    required this.hasPinned,
    required this.chips,
  });
  final ValueNotifier<String?> query;
  final bool hasPinned;
  final Widget chips;

  @override
  Widget build(BuildContext context) {
    final backButton = detailNavigationBackButton(context);
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (backButton != null) ...[
              backButton,
              const SizedBox(width: 20),
            ],
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: SearchField(
                  initialText: query.value,
                  onSubmitted: (value) => query.value = value,
                ),
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
  const _SearchFilterChips({required this.hasPinned});
  final bool hasPinned;

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
            onSelected: (_) => ref
                .read(globalSearchScopeProvider.notifier)
                .update(GlobalSearchSourceFilter.pinned),
          ),
          const SizedBox(width: 8),
        ],
        FilterChip(
          showCheckmark: false,
          avatar: const Icon(Icons.done_all_rounded, size: 18),
          label: Text(context.l10n.all),
          selected: !hasPinned || scope == GlobalSearchSourceFilter.all,
          onSelected: (_) => ref
              .read(globalSearchScopeProvider.notifier)
              .update(GlobalSearchSourceFilter.all),
        ),
        const SizedBox(width: 12),
        FilterChip(
          showCheckmark: false,
          avatar: const Icon(Icons.filter_list_rounded, size: 18),
          label: Text(context.l10n.hasResults),
          selected: onlyHasResults,
          onSelected: (_) =>
              ref.read(globalSearchOnlyHasResultsProvider.notifier).state =
                  !onlyHasResults,
        ),
      ],
    );
  }
}
