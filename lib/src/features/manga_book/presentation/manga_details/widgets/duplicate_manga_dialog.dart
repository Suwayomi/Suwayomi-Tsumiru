// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Komikku-parity "possible duplicates" dialog (#118/#117 design,
// 2026-07-24). Single mode fires on an individual add; bulk mode is the
// paused-per-duplicate step of the multi-select add flow. The dialog never
// navigates itself — long-press and "Show entry" report the target manga
// via [onOpenEntry] and pop `openedEntry`; the caller navigates once the
// dialog has closed.

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../../../widgets/manga_cover/widgets/manga_badges.dart';
import '../../../domain/manga/manga_model.dart';

enum DuplicateDialogResult {
  addAnyway,
  cancel,
  openedEntry,
  migrated,
  // Bulk-only.
  allowAll,
  skipIt,
  skipAll,
}

typedef MigrateDuplicate = Future<bool> Function(MangaDto duplicate);

class DuplicateMangaDialog extends StatelessWidget {
  const DuplicateMangaDialog({
    super.key,
    required this.candidate,
    required this.duplicates,
    required this.certainIds,
    required this.trackerNameOf,
    this.onMigrate,
    this.onOpenEntry,
    this.bulk = false,
  });

  /// The manga being added.
  final MangaDto candidate;

  /// The existing library entries flagged as possible duplicates.
  final List<MangaDto> duplicates;

  /// Ids (from [duplicates]) that share a tracker binding with [candidate] —
  /// a certain match, not just a title/description heuristic.
  final Set<int> certainIds;

  /// Resolves a tracker id to its display name; null renders the generic
  /// "Same tracker entry" chip instead of naming the service.
  final String? Function(int trackerId) trackerNameOf;

  /// Migrates a tapped duplicate into [candidate]. Supplied in both single
  /// and bulk mode by the caller — null only matters as a defensive
  /// fallback (open the entry instead of migrating).
  final MigrateDuplicate? onMigrate;

  /// Reports which manga a long-press (or bulk's "Show entry") targeted,
  /// called before the dialog pops `openedEntry`. The caller navigates
  /// after the dialog closes — this dialog never pushes a route itself.
  final ValueChanged<MangaDto>? onOpenEntry;

  /// Bulk-add mode: adds Allow all / Skip it / Skip all / Show entry.
  final bool bulk;

  Future<void> _handleCardTap(BuildContext context, MangaDto duplicate) async {
    if (onMigrate == null) {
      onOpenEntry?.call(duplicate);
      Navigator.of(context).pop(DuplicateDialogResult.openedEntry);
      return;
    }
    final migrated = await onMigrate!(duplicate);
    if (!context.mounted || !migrated) return;
    Navigator.of(context).pop(DuplicateDialogResult.migrated);
  }

  void _handleCardLongPress(BuildContext context, MangaDto duplicate) {
    onOpenEntry?.call(duplicate);
    Navigator.of(context).pop(DuplicateDialogResult.openedEntry);
  }

  void _handleShowEntry(BuildContext context) {
    onOpenEntry?.call(candidate);
    Navigator.of(context).pop(DuplicateDialogResult.openedEntry);
  }

  void _pop(BuildContext context, DuplicateDialogResult result) =>
      Navigator.of(context).pop(result);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.possibleDuplicatesTitle),
      content: SizedBox(
        width: double.maxFinite,
        // The card row has a fixed height regardless; wrapping the whole
        // content in a scroll view (rather than a bare Column) means a
        // small dialog viewport scrolls instead of overflowing.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(candidate.title, style: context.textTheme.titleMedium),
              const Gap(4),
              Text(
                context.l10n.possibleDuplicatesBody,
                style: context.textTheme.bodyMedium,
              ),
              const Gap(12),
              SizedBox(
                height: 300,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: duplicates.length,
                  separatorBuilder: (_, _) => const Gap(8),
                  itemBuilder: (context, index) {
                    final duplicate = duplicates[index];
                    return _DuplicateCard(
                      duplicate: duplicate,
                      candidate: candidate,
                      isCertain: certainIds.contains(duplicate.id),
                      trackerNameOf: trackerNameOf,
                      onTap: () => _handleCardTap(context, duplicate),
                      onLongPress: () =>
                          _handleCardLongPress(context, duplicate),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: () => _pop(context, DuplicateDialogResult.addAnyway),
              child: Text(context.l10n.actionAddAnyway),
            ),
            if (bulk) ...[
              TextButton(
                onPressed: () => _pop(context, DuplicateDialogResult.allowAll),
                child: Text(context.l10n.duplicateAllowAll),
              ),
              TextButton(
                onPressed: () => _pop(context, DuplicateDialogResult.skipIt),
                child: Text(context.l10n.duplicateSkipIt),
              ),
              TextButton(
                onPressed: () => _pop(context, DuplicateDialogResult.skipAll),
                child: Text(context.l10n.duplicateSkipAll),
              ),
              TextButton(
                onPressed: () => _handleShowEntry(context),
                child: Text(context.l10n.actionShowEntry),
              ),
            ],
            TextButton(
              onPressed: () => _pop(context, DuplicateDialogResult.cancel),
              child: Text(context.l10n.cancel),
            ),
          ],
        ),
      ],
    );
  }
}

const double _kCardWidth = 140;

class _DuplicateCard extends StatelessWidget {
  const _DuplicateCard({
    required this.duplicate,
    required this.candidate,
    required this.isCertain,
    required this.trackerNameOf,
    required this.onTap,
    required this.onLongPress,
  });

  final MangaDto duplicate;
  final MangaDto candidate;
  final bool isCertain;
  final String? Function(int trackerId) trackerNameOf;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// The tracker binding [duplicate] shares with [candidate], if any — used
  /// only to pick which tracker name to show in the certain-match chip.
  /// [isCertain] (computed by the matcher) is the actual gate; this is a
  /// best-effort lookup for the label.
  int? get _sharedTrackerId {
    for (final node in duplicate.trackRecords.nodes) {
      final shared = candidate.trackRecords.nodes.any(
        (c) => c.trackerId == node.trackerId && c.remoteId == node.remoteId,
      );
      if (shared) return node.trackerId;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final status = MangaStatus.fromJson(duplicate.status.name);
    final author = duplicate.author;
    final artist = duplicate.artist;
    final showArtist = artist.isNotBlank && artist != author;
    final sourceName =
        duplicate.source?.displayName ??
        duplicate.source?.name ??
        context.l10n.unknownSource;

    return SizedBox(
      width: _kCardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _kCardWidth,
            height: 150,
            // Loose fit let the cover shrink to the art's aspect, leaving
            // the corner badges floating in the leftover space.
            child: Stack(
              fit: StackFit.expand,
              children: [
                MangaCoverGridTile(
                  manga: duplicate,
                  showBadges: false,
                  showTitle: false,
                  showDarkOverlay: false,
                  onPressed: onTap,
                  onLongPress: onLongPress,
                ),
                Positioned(
                  left: 4,
                  top: 4,
                  child: MangaBadge(
                    text: '${duplicate.chapters.totalCount}',
                    color: context.theme.colorScheme.secondary,
                    textColor: context.theme.colorScheme.onSecondary,
                  ),
                ),
                if (duplicate.unreadCount > 0)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: MangaBadge(
                      text: '${duplicate.unreadCount}',
                      color: context.theme.colorScheme.primary,
                      textColor: context.theme.colorScheme.onPrimary,
                      side: BadgeSide.right,
                    ),
                  ),
              ],
            ),
          ),
          const Gap(4),
          GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  duplicate.title,
                  style: context.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
                if (author.isNotBlank)
                  _DetailRow(icon: Icons.person_outline_rounded, text: author!),
                if (showArtist)
                  _DetailRow(icon: Icons.brush_rounded, text: artist!),
                _DetailRow(icon: status.icon, text: status.toLocale(context)),
                if (isCertain) ...[
                  const Gap(4),
                  _CertainChip(
                    label: switch (trackerNameOf(_sharedTrackerId ?? -1)) {
                      final String tracker =>
                        context.l10n.duplicateSameTrackerEntry(tracker),
                      null => context.l10n.duplicateSameTrackerEntryGeneric,
                    },
                  ),
                ],
                const Gap(4),
                Text(
                  sourceName,
                  style: context.textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: context.textTheme.bodySmall?.color),
          const Gap(4),
          Expanded(
            child: Text(
              text,
              style: context.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
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
        borderRadius: KBorderRadius.r8.radius,
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
