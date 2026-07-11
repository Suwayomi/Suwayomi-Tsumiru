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
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/search_field.dart';
import '../source/controller/source_controller.dart';
import 'controller/source_quick_search_controller.dart';
import 'widgets/source_short_search.dart';

class GlobalSearchScreen extends HookConsumerWidget {
  const GlobalSearchScreen({super.key, this.initialQuery});
  final String? initialQuery;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState(initialQuery);
    final quickSearchResult =
        ref.watch(quickSearchResultsProvider(query: query.value));
    final scope = ref.watch(globalSearchScopeProvider);
    final onlyHasResults = ref.watch(globalSearchOnlyHasResultsProvider);
    final hasPinned = ref.watch(pinnedSourcesProvider).isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.globalSearch),
        bottom: PreferredSize(
          preferredSize: kCalculateAppBarBottomSize([true]),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: SearchField(
                  initialText: query.value,
                  onSubmitted: (value) => query.value = value,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Filter chips: Pinned / All source scope + Has results.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
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
                  onSelected: (_) => ref
                      .read(globalSearchOnlyHasResultsProvider.notifier)
                      .state = !onlyHasResults,
                ),
              ],
            ),
          ),
          Expanded(
            child: quickSearchResult.showUiWhenData(
              context,
              (data) {
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
                        .where((e) =>
                            (e.mangaList.valueOrNull?.isNotEmpty).ifNull())
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
              },
            ),
          ),
        ],
      ),
    );
  }
}
