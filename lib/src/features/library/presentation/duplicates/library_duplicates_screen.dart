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
import '../../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../../widgets/selection_action_bar.dart';
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
    // Offline data has no fresh tracker/description fields to trust, so the
    // scan itself never runs the description pass while unreachable — even
    // if the persisted toggle is on.
    final checkDescriptions = wantsDescriptionCheck && !offline;
    final scanProvider = libraryDuplicatesProvider(
      checkDescriptions: checkDescriptions,
    );
    final scan = ref.watch(scanProvider);
    final libraryAsync = ref.watch(libraryMangaListProvider);
    final trackerNames = ref.watch(libraryTrackerNamesProvider);

    // Long-press to select; removals filter these groups in memory (Task 13)
    // rather than invalidating the read-once scan provider.
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
      );
      if (confirmed != true || !context.mounted) return;

      // The container outlives this widget, so a mid-loop unmount can't leave
      // successful removals unreflected in the rest of the app.
      final container = ProviderScope.containerOf(context, listen: false);
      final remover = container.read(duplicateEntryRemoverProvider);
      final removed = <int>[];
      for (final id in ids) {
        try {
          // The container backs the removal, so an unmount mid-await still
          // completes the purge instead of surfacing as a removal failure.
          await remover(container, id);
          removed.add(id);
        } catch (_) {
          // Stop on the first failure so a broken removal is never hidden — the
          // snackbar below reports how many of the requested ids actually left.
          break;
        }
      }

      // Refresh the rest of the app's library view; the scan provider reads the
      // library once (Task 11), so this cannot re-trigger the O(n²) scan. Runs
      // before the mounted check so an unmount mid-loop can't leave it stale.
      container.invalidate(libraryMangaListProvider);

      if (!context.mounted) return;
      removedIds.value = {...removedIds.value, ...removed};
      clearSelection();
      final message = removed.length < ids.length
          ? context.l10n.duplicatesRemovedPartial(removed.length, ids.length)
          : context.l10n.duplicatesRemoved(removed.length);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }

    final body = Column(
      children: [
        if (offline)
          _OfflineBanner(
            onReconnect: () => const ConnectionRoute().push(context),
          ),
        SwitchListTile(
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

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.duplicatedEntries),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: context.l10n.scanForDuplicates,
            onPressed: () => ref.read(scanProvider.notifier).rescan(),
          ),
        ],
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

/// A tracker id held by at least two of [members] — mirrors the matcher's
/// own "shared tracker key" test, but works from live [MangaDto]s so the UI
/// can name the tracker without threading ids back through [DupGroup].
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
        SizedBox(
          // Derived, not a literal: the cover grew when it was corrected to
          // 2:3, and a fixed strip height clipped the title under it.
          height: mangaCoverBoxHeight(_kCardWidth) + _kMemberCardTextExtent,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: members.length,
            separatorBuilder: (_, _) => const Gap(8),
            itemBuilder: (context, index) => _MemberCard(
              manga: members[index],
              selected: selectedIds.contains(members[index].id),
              selecting: selecting,
              onToggleSelection: onToggleSelection,
            ),
          ),
        ),
      ],
    );
  }
}

const double _kCardWidth = 120;

/// Title + source lines and their gaps under each cover in the strip.
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
              // While selecting, a tap toggles the cover instead of opening it.
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
