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
import '../../../utils/theme/brand.dart';
import '../../../widgets/manga_cover/list/manga_cover_list_tile.dart';
import '../../migration/domain/migration_models.dart';
import '../data/updates/updates_repository.dart';
import '../domain/manga/manga_model.dart';
import '../domain/update_status/update_status_model.dart';
import 'update_status_popup_menu.dart';

class UpdateStatusSummaryDialog extends ConsumerWidget {
  const UpdateStatusSummaryDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusUpdate = ref.watch(updateSummaryProvider);
    final statusUpdateStream = ref.watch(updatesSocketProvider);
    final AsyncValue<UpdateStatusDto?> finalStatus =
        (statusUpdateStream.value?.total.isGreaterThan(0)).ifNull()
            ? statusUpdateStream
            : statusUpdate;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.updatesSummary),
        actions: const [UpdateStatusPopupMenu(showSummaryButton: false)],
      ),
      body: finalStatus.showUiWhenData(
        context,
        (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(updateSummaryProvider.future),
          child: ListView(
            children: [
              if ((data?.runningJobs.mangaList).isNotBlank)
                UpdateStatusExpansionTile(
                  mangas: data!.runningJobs.mangaList,
                  title: context.l10n.running,
                  initiallyExpanded: true,
                ),
              if ((data?.pendingJobs.mangaList).isNotBlank)
                UpdateStatusExpansionTile(
                  mangas: data!.pendingJobs.mangaList,
                  title: context.l10n.pending,
                ),
              if ((data?.completeJobs.mangaList).isNotBlank)
                UpdateStatusExpansionTile(
                  mangas: data!.completeJobs.mangaList,
                  title: context.l10n.completed,
                ),
              if ((data?.failedJobs.mangaList).isNotBlank)
                UpdateStatusExpansionTile(
                  mangas: data!.failedJobs.mangaList,
                  title: context.l10n.failed,
                  initiallyExpanded: true,
                  onMigrate: (manga) => MigrationGlobalSearchRoute(
                    $extra: MigrationRouteData(sourceManga: manga),
                  ).push(context),
                ),
            ],
          ),
        ),
        refresh: () => ref.invalidate(updateSummaryProvider),
      ),
    );
  }
}

class UpdateStatusExpansionTile extends StatelessWidget {
  const UpdateStatusExpansionTile({
    super.key,
    required this.mangas,
    required this.title,
    this.initiallyExpanded = false,
    this.onMigrate,
  });
  final List<MangaDto> mangas;
  final String title;
  final bool initiallyExpanded;

  /// When set, each row shows a Migrate button that runs this with the row's
  /// series — wired only for failed updates, whose source may have moved away.
  final void Function(MangaDto manga)? onMigrate;
  @override
  Widget build(BuildContext context) {
    final onMigrate = this.onMigrate;
    return ExpansionTile(
      title: Text("$title (${mangas.length.padLeft()})"),
      initiallyExpanded: initiallyExpanded,
      textColor: context.theme.colorScheme.primary,
      iconColor: context.theme.colorScheme.primary,
      shape: const RoundedRectangleBorder(),
      children: mangas
          .map((e) => MangaCoverListTile(
                manga: e,
                showCountBadges: true,
                onPressed: () => MangaRoute(mangaId: e.id).push(context),
                trailing: onMigrate != null
                    ? _MigrateButton(onPressed: () => onMigrate(e))
                    : null,
              ))
          .toList(),
    );
  }
}

/// A pill button that sends a series into the migration flow — shown on failed
/// library-update rows so a dead source can be swapped without hunting for the
/// entry.
class _MigrateButton extends StatelessWidget {
  const _MigrateButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    final accent = brandBrightAccent(cs);
    return Padding(
      padding: KEdgeInsets.h8.size,
      child: Material(
        color: cs.primary.withValues(alpha: 0.14),
        shape: StadiumBorder(
          side: BorderSide(color: cs.primary.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_horiz_rounded, size: 17, color: accent),
                const SizedBox(width: 6),
                Text(
                  context.l10n.migrate,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
