// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/compact_switch.dart';
import '../../../../widgets/cover_row_section.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../../widgets/selection_action_bar.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../../offline/data/server_reachability.dart';
import '../../domain/duplicate_matcher.dart';
import '../library/controller/library_controller.dart';
import '../library/controller/library_manga_list.dart';
import 'controller/library_duplicates_controller.dart';

class LibraryDuplicatesScreen extends HookConsumerWidget {
  const LibraryDuplicatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(serverUnreachableProvider);
    final wantsDescriptionCheck = ref
        .watch(libraryDuplicatesCheckDescriptionProvider)
        .ifNull(false);
    // Offline data lacks fresh tracker and description fields for description matching.
    final checkDescriptions = wantsDescriptionCheck && !offline;
    final scanProvider = libraryDuplicatesProvider(
      checkDescriptions: checkDescriptions,
    );
    final scan = ref.watch(scanProvider);
    final libraryAsync = ref.watch(libraryMangaListProvider);
    final trackerNames = ref.watch(libraryTrackerNamesProvider);

    // Filter removals in memory without invalidating the read-once O(n²) scan.
    final selection = useState<Set<int>>(const {});
    final removedIds = useState<Set<int>>(const {});
    final selecting = selection.value.isNotEmpty;

    void clearSelection() => selection.value = const {};

    void toggleSelection(int id) {
      final next = {...selection.value};
      next.contains(id) ? next.remove(id) : next.add(id);
      selection.value = next;
    }

    Future<void> removeSelection() async {
      final ids = selection.value.toList();
      if (ids.isEmpty) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(context.l10n.duplicatesRemoveConfirm(ids.length)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.l10n.remove),
            ),
          ],
        ),
        animationStyle: context.motionStyle,
      );
      if (confirmed != true || !context.mounted) return;

      // The container outlives the widget, so removals and invalidation survive unmounts.
      final container = ProviderScope.containerOf(context, listen: false);
      final remover = container.read(duplicateEntryRemoverProvider);
      final removed = <int>[];
      for (final id in ids) {
        try {
          await remover(container, id);
          removed.add(id);
        } catch (_) {
          break;
        }
      }

      // Invalidate before checking mounted; the read-once scan does not watch this provider.
      container.invalidate(libraryMangaListProvider);

      if (!context.mounted) return;
      removedIds.value = {...removedIds.value, ...removed};
      clearSelection();
      final message = removed.length < ids.length
          ? context.l10n.duplicatesRemovedPartial(removed.length, ids.length)
          : context.l10n.duplicatesRemoved(removed.length);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
        snackBarAnimationStyle: context.snackBarMotionStyle,
      );
    }

    final body = Column(
      children: [
        if (offline)
          _OfflineBanner(
            onReconnect: () => const ConnectionRoute().push(context),
          ),
        CompactSwitchListTile(
          title: Text(context.l10n.checkDescription),
          value: checkDescriptions,
          onChanged: offline
              ? null
              : (value) => ref
                    .read(libraryDuplicatesCheckDescriptionProvider.notifier)
                    .update(value),
        ),
        Expanded(
          child: scan.when(
            data: (groups) => _GroupList(
              groups: visibleDuplicateGroups(groups, removedIds.value),
              library: libraryAsync.asData?.value ?? const [],
              trackerNameOf: (id) => trackerNames[id],
              selectedIds: selection.value,
              selecting: selecting,
              onToggleSelection: toggleSelection,
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('$error')),
          ),
        ),
      ],
    );

    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.duplicatedEntries);
    final actions = <Widget>[
      IconButton(
        icon: const Icon(Icons.refresh_rounded),
        tooltip: context.l10n.scanForDuplicates,
        onPressed: () => ref.read(scanProvider.notifier).rescan(),
      ),
    ];
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
              leading: detailNavigationBackButton(context),
              title: title,
              actions: actions,
            ),
      body: PopScope(
        canPop: !selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) clearSelection();
        },
        child: Stack(
          children: [
            body,
            if (selecting)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SelectionActionBar(
                  clearsSystemNav: true,
                  leading: [
                    IconButton(
                      tooltip: context.l10n.cancel,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: clearSelection,
                    ),
                    Text(
                      '${selection.value.length}',
                      style: context.textTheme.titleMedium,
                    ),
                  ],
                  actions: [
                    IconButton(
                      tooltip: offline
                          ? context.l10n.duplicatesRemoveOfflineTooltip
                          : context.l10n.remove,
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: offline ? null : removeSelection,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      actions: actions,
      child: scaffold,
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onReconnect});

  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text(context.l10n.duplicatesOfflineTitleOnly),
      leading: const Icon(Icons.cloud_off_rounded),
      actions: [
        TextButton(
          onPressed: onReconnect,
          child: Text(context.l10n.serverUnreachableAction),
        ),
      ],
    );
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({
    required this.groups,
    required this.library,
    required this.trackerNameOf,
    required this.selectedIds,
    required this.selecting,
    required this.onToggleSelection,
  });

  final List<DupGroup> groups;
  final List<MangaDto> library;
  final String? Function(int trackerId) trackerNameOf;
  final Set<int> selectedIds;
  final bool selecting;
  final void Function(int mangaId) onToggleSelection;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return Center(child: Text(context.l10n.noResultsFound));
    }
    final byId = {for (final manga in library) manga.id: manga};
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) => _GroupTile(
        group: groups[index],
        members: [
          for (final id in groups[index].memberIds)
            if (byId[id] != null) byId[id]!,
        ],
        trackerNameOf: trackerNameOf,
        selectedIds: selectedIds,
        selecting: selecting,
        onToggleSelection: onToggleSelection,
      ),
    );
  }
}

/// A tracker shared by at least two members, excluding unrelated singleton bindings.
int? _sharedTrackerId(List<MangaDto> members) {
  final holderCounts = <int, int>{};
  for (final manga in members) {
    final trackerIdsHeld = {
      for (final node in manga.trackRecords.nodes) node.trackerId,
    };
    for (final trackerId in trackerIdsHeld) {
      holderCounts[trackerId] = (holderCounts[trackerId] ?? 0) + 1;
    }
  }
  for (final entry in holderCounts.entries) {
    if (entry.value >= 2) return entry.key;
  }
  return null;
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.members,
    required this.trackerNameOf,
    required this.selectedIds,
    required this.selecting,
    required this.onToggleSelection,
  });

  final DupGroup group;
  final List<MangaDto> members;
  final String? Function(int trackerId) trackerNameOf;
  final Set<int> selectedIds;
  final bool selecting;
  final void Function(int mangaId) onToggleSelection;

  @override
  Widget build(BuildContext context) {
    final isCertain = group.reasons.contains(DupReason.tracker);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  group.header,
                  style: context.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isCertain) ...[
                const Gap(8),
                _CertainChip(
                  label: switch (trackerNameOf(
                    _sharedTrackerId(members) ?? -1,
                  )) {
                    final String tracker =>
                      context.l10n.duplicateSameTrackerEntry(tracker),
                    null => context.l10n.duplicateSameTrackerEntryGeneric,
                  },
                ),
              ],
            ],
          ),
        ),
        const Gap(8),
        // Derive strip height from cover height so cover aspect changes cannot clip text.
        CoverRowSection(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          height: mangaCoverBoxHeight(_kCardWidth) + _kMemberCardTextExtent,
          itemCount: members.length,
          itemBuilder: (context, index) => _MemberCard(
            manga: members[index],
            selected: selectedIds.contains(members[index].id),
            selecting: selecting,
            onToggleSelection: onToggleSelection,
          ),
          separatorBuilder: (_, _) => const Gap(8),
        ),
      ],
    );
  }
}

const double _kCardWidth = 120;

/// Source text needs ~20 px at default scale; reserve extra room for larger text.
const double _kMemberCardTextExtent = 40;

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.manga,
    required this.selected,
    required this.selecting,
    required this.onToggleSelection,
  });

  final MangaDto manga;
  final bool selected;
  final bool selecting;
  final void Function(int mangaId) onToggleSelection;

  @override
  Widget build(BuildContext context) {
    final sourceName =
        manga.source?.displayName ??
        manga.source?.name ??
        context.l10n.unknownSource;
    return SizedBox(
      width: _kCardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _kCardWidth,
            height: mangaCoverBoxHeight(_kCardWidth),
            child: MangaCoverGridTile(
              manga: manga,
              selected: selected,
              onPressed: selecting
                  ? () => onToggleSelection(manga.id)
                  : () => MangaRoute(mangaId: manga.id).push(context),
              onLongPress: () => onToggleSelection(manga.id),
            ),
          ),
          const Gap(4),
          Text(
            sourceName,
            style: context.textTheme.labelSmall,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

class _CertainChip extends StatelessWidget {
  const _CertainChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: context.textTheme.labelSmall?.copyWith(
            color: context.theme.colorScheme.onPrimaryContainer,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }
}
