// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/app_sizes.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../widgets/desktop/desktop_top_bar.dart';
import '../../../widgets/emoticons.dart';
import '../../../widgets/search_field.dart';
import '../../../widgets/server_image.dart';
import '../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../quick_open/presentation/unified_search/desktop_search_field.dart';
import '../../quick_open/presentation/unified_search/phone_search_view.dart';
import '../../quick_open/presentation/unified_search/unified_search_results.dart';
import '../../settings/presentation/library/widgets/persistent_search_bar/persistent_search_bar.dart';
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
    final desktop = context.usesDesktopShell;
    final phone = context.windowSizeClass == WindowSizeClass.compact;
    final persistentBox =
        phone && ref.watch(libraryPersistentSearchBarProvider).ifNull();
    final historyTop = [
      for (final group in historyGroups) ...group.items,
    ].take(3).toList();
    final topBar = showsMergedTopBar(context);
    final search = DesktopSearchField(
      query: searchQuery,
      onChanged: (value) =>
          ref.read(historySearchQueryProvider.notifier).updateQuery(value),
      onNavigate: () =>
          ref.read(historySearchQueryProvider.notifier).clearQuery(),
      // Build synchronously so selectable rows receive the first keyboard indices in visual order.
      leadingBuilder: (selectable) => [
        if (historyTop.isNotEmpty) SearchSectionHeader(l10n.history),
        for (final item in historyTop)
          selectable(
            action: () {
              MangaRoute(mangaId: item.manga.id).push(context);
              ref.read(historySearchQueryProvider.notifier).clearQuery();
            },
            tile: (onTap) => HistoryDropdownRow(item: item, onTap: onTap),
          ),
      ],
      hasLeadingResults: historyTop.isNotEmpty,
      onSubmitLeading: historyTop.isEmpty
          ? null
          : () {
              MangaRoute(mangaId: historyTop.first.manga.id).push(context);
              return true;
            },
    );
    final actions = <Widget>[
      if (phone && !persistentBox) ...[
        const PhoneSearchClearFilter(origin: PhoneSearchOrigin.history),
        const PhoneSearchEntry(origin: PhoneSearchOrigin.history),
      ],
      IconButton(
        icon: const Icon(FluentIcons.filter_24_regular),
        tooltip: l10n.filter,
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
        onPressed: () => ref.read(readingHistoryProvider.notifier).refresh(),
        icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
      ),
    ];
    final backButton = detailNavigationBackButton(context);
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
              leading: backButton,
              title: desktop
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: search,
                      ),
                    )
                  : Text(l10n.history),
              bottom: persistentBox
                  ? const PhoneSearchBoxBottom(
                      origin: PhoneSearchOrigin.history,
                    )
                  : null,
              actions: actions,
            ),
      body: Column(
        children: [
          if (!desktop && !phone)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: context.windowSizeClass >= WindowSizeClass.expanded
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
          Expanded(
            child: historyState.when(
              data: (data) {
                if (data == null || data.isEmpty) {
                  return const HistoryEmptyState();
                }

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
    return topBar
        ? TopBarSlot(
            content: desktopSearchSlotContent(
              leading: backButton,
              search: search,
              actions: actions,
            ),
            minWidth: searchTopBarSlotMinWidth(
              actions.length,
              backButton != null,
            ),
            child: scaffold,
          )
        : scaffold;
  }
}

/// The caller supplies the selectable wrapper to place history rows first in keyboard order.
class HistoryDropdownRow extends StatelessWidget {
  const HistoryDropdownRow({
    super.key,
    required this.item,
    required this.onTap,
  });

  final HistoryItemDto item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: ServerImage(
          imageUrl: item.manga.displayCoverUrl,
          fallbackImageUrl: item.manga.thumbnailUrl,
          coverVersion: item.manga.coverVersion,
          fallbackCoverVersion: item.manga.thumbnailUrlLastFetched,
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
      onTap: onTap,
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
            const Emoticons(iconData: FluentIcons.history_24_regular),
            const SizedBox(height: 16),
            Text(
              l10n.noHistoryFound,
              style: context.theme.textTheme.headlineSmall,
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
            const Emoticons(iconData: FluentIcons.search_info_24_regular),
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
            const Emoticons(iconData: FluentIcons.error_circle_24_regular),
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
