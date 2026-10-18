// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/app_sizes.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../widgets/emoticons.dart';
import '../../../widgets/search_field.dart';
import '../../../widgets/server_image.dart';
import '../../quick_open/presentation/unified_search/desktop_search_field.dart';
import '../../quick_open/presentation/unified_search/unified_search_results.dart';
import '../domain/history_item.dart';
import 'history_controller.dart';
import 'widgets/history_filter.dart';
import 'widgets/history_group_widget.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final historyGroups = ref.watch(filteredHistoryGroupsProvider);
    final historyState = ref.watch(readingHistoryProvider);
    final searchQuery = ref.watch(historySearchQueryProvider);
    final hasActiveFilters = ref.watch(historyHasActiveFiltersProvider);
    final desktop = context.isDesktop;
    // Dropdown-first matches, same live filter the list uses.
    final historyTop = [
      for (final group in historyGroups) ...group.items,
    ].take(3).toList();

    return Scaffold(
      appBar: AppBar(
        // Desktop uses the one search box: it filters the list live AND opens
        // the unified dropdown with History first. The sidebar names the page.
        title: desktop
            ? Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: DesktopSearchField(
                    query: searchQuery,
                    onChanged: (value) => ref
                        .read(historySearchQueryProvider.notifier)
                        .updateQuery(value),
                    onNavigate: () => ref
                        .read(historySearchQueryProvider.notifier)
                        .clearQuery(),
                    leading: [
                      if (historyTop.isNotEmpty)
                        HistoryDropdownSection(items: historyTop),
                    ],
                    hasLeadingResults: historyTop.isNotEmpty,
                  ),
                ),
              )
            : Text(l10n.history),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            tooltip: l10n.filter,
            // Tinted while filtered, so a short list reads as "filtered" rather
            // than "nothing read". Komikku uses amber; ours comes from the theme.
            color: hasActiveFilters ? context.theme.colorScheme.primary : null,
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: RoundedRectangleBorder(
                borderRadius: KBorderRadius.rT16.radius,
              ),
              clipBehavior: Clip.hardEdge,
              builder: (_) => const HistoryFilterSheet(),
              sheetAnimationStyle: context.motionStyle,
            ),
          ),
          IconButton(
            onPressed: () =>
                ref.read(readingHistoryProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // Phone/tablet keep their own search bar; desktop searches from the
          // header box above, so a second box would double-filter.
          if (!desktop)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: context.isLargeTablet
                    ? context.widthScale(scale: .5)
                    : null,
                child: Padding(
                  padding: KEdgeInsets.h16v4.size,
                  child: SearchField(
                    initialText: searchQuery,
                    onChanged: (query) => ref
                        .read(historySearchQueryProvider.notifier)
                        .updateQuery(query ?? ''),
                    onSubmitted: (query) => ref
                        .read(historySearchQueryProvider.notifier)
                        .updateQuery(query ?? ''),
                    labelText: l10n.searchHistory,
                    autofocus: false,
                  ),
                ),
              ),
            ),
          // History content
          Expanded(
            child: historyState.when(
              data: (data) {
                if (data == null || data.isEmpty) {
                  return const HistoryEmptyState();
                }

                // Filters can empty the list just as a search can; without this
                // the builder below renders a blank page with no explanation.
                if (historyGroups.isEmpty &&
                    (searchQuery.isNotBlank || hasActiveFilters)) {
                  return const HistoryNoSearchResults();
                }

                final notifier = ref.read(readingHistoryProvider.notifier);
                return RefreshIndicator(
                  onRefresh: notifier.refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: historyGroups.length,
                    itemBuilder: (context, index) {
                      final group = historyGroups[index];
                      return HistoryGroupWidget(group: group);
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => HistoryErrorState(
                error: error,
                onRetry: () =>
                    ref.read(readingHistoryProvider.notifier).refresh(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// First dropdown section on desktop History: up to 3 matching entries in the
/// same row look as the unified Library rows (cover, series title, chapter).
/// Opening one clears the header query, like every dropdown result.
class HistoryDropdownSection extends ConsumerWidget {
  const HistoryDropdownSection({super.key, required this.items});

  final List<HistoryItemDto> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SearchSectionHeader(context.l10n.history),
        for (final item in items)
          ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: ServerImage(
                imageUrl: item.manga.thumbnailUrl ?? "",
                size: const Size(40, 56),
              ),
            ),
            title: Text(
              item.manga.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall,
            ),
            onTap: () {
              MangaRoute(mangaId: item.manga.id).push(context);
              ref.read(historySearchQueryProvider.notifier).clearQuery();
            },
          ),
      ],
    );
  }
}

class HistoryEmptyState extends StatelessWidget {
  const HistoryEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Emoticons(iconData: Icons.history),
            const SizedBox(height: 16),
            Text(
              l10n.noHistoryFound,
              style: context.theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.startReadingToSeeHistory,
              style: context.theme.textTheme.bodyMedium?.copyWith(
                color: context.theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class HistoryNoSearchResults extends StatelessWidget {
  const HistoryNoSearchResults({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Emoticons(iconData: Icons.search_off),
            const SizedBox(height: 16),
            Text(
              l10n.noSearchResults,
              style: context.theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.tryDifferentSearchTerm,
              style: context.theme.textTheme.bodyMedium?.copyWith(
                color: context.theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class HistoryErrorState extends StatelessWidget {
  const HistoryErrorState({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Emoticons(iconData: Icons.error_outline),
            const SizedBox(height: 16),
            Text(
              l10n.errorOccurred,
              style: context.theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: context.theme.textTheme.bodyMedium?.copyWith(
                color: context.theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}
