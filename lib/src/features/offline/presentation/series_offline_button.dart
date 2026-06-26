// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../manga_book/presentation/manga_details/widgets/manga_action_button.dart';
import '../data/offline_database.dart';
import '../data/offline_download_providers.dart';
import '../data/offline_repository.dart';

/// The prominent per-series offline control that lives in the manga-details
/// action row (beside "In Library"). Shows whether the series is on the device
/// and opens an action sheet to download / auto-keep / remove it. Replaces the
/// old buried app-bar pin.
class SeriesOfflineButton extends ConsumerWidget {
  const SeriesOfflineButton({super.key, required this.mangaId});

  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(offlineEnabledProvider)) return const SizedBox.shrink();
    final progress =
        ref.watch(mangaOfflineProgressProvider(mangaId)).valueOrNull;
    final downloaded = progress?.downloaded ?? 0;
    final inFlight = progress?.inFlight ?? 0;
    final onDevice = downloaded > 0;
    final downloading = inFlight > 0;
    return MangaActionButton(
      active: onDevice || downloading,
      icon: downloading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(onDevice
              ? Icons.offline_pin_rounded
              : Icons.download_for_offline_outlined),
      label: downloading
          ? context.l10n.offlineDownloadingCount(inFlight)
          : onDevice
              ? context.l10n.offlineOnDevice
              : context.l10n.offlineDownloadAction,
      onPressed: () => _openSheet(context, ref, onDevice),
    );
  }

  void _openSheet(BuildContext context, WidgetRef ref, bool onDevice) {
    final rule = ref.read(mangaKeepRuleProvider(mangaId)).valueOrNull ??
        OfflineKeepRule.off;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Explain what this sheet does — offline (device) copies, distinct
            // from the server download up top.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sheetContext.l10n.offlineSheetTitle,
                    style: sheetContext.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sheetContext.l10n.offlineSheetSubtitle,
                    style: TextStyle(
                      color: sheetContext.theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: Text(sheetContext.l10n.offlineDownloadAll),
              trailing: rule == OfflineKeepRule.all
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => _apply(sheetContext, ref, OfflineKeepRule.all),
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_added_outlined),
              title: Text(sheetContext.l10n.keepOfflineNUnread),
              trailing: rule == OfflineKeepRule.nUnread
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => _apply(sheetContext, ref, OfflineKeepRule.nUnread),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(sheetContext.l10n.keepOfflineAllUnread),
              trailing: rule == OfflineKeepRule.allUnread
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => _apply(sheetContext, ref, OfflineKeepRule.allUnread),
            ),
            if (onDevice) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(sheetContext.l10n.offlineRemoveSeries),
                onTap: () => _removeAll(sheetContext, ref),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _apply(
      BuildContext sheetContext, WidgetRef ref, OfflineKeepRule rule) async {
    final messenger = ScaffoldMessenger.of(sheetContext);
    final toast = sheetContext.l10n.offlineDownloadingToast;
    Navigator.of(sheetContext).pop();
    await ref.read(offlineDatabaseProvider).setKeepRule(mangaId, rule, 3);
    ref.invalidate(mangaKeepRuleProvider(mangaId));
    messenger.showSnackBar(SnackBar(content: Text(toast)));
    // The reconcile may pull many chapters; run it in the background and refresh
    // the on-device count as it completes.
    unawaited(reconcileMangaWidget(ref, mangaId)
        .then((_) => ref.invalidate(mangaDownloadedCountProvider(mangaId))));
  }

  Future<void> _removeAll(BuildContext sheetContext, WidgetRef ref) async {
    Navigator.of(sheetContext).pop();
    final db = ref.read(offlineDatabaseProvider);
    await db.setKeepRule(mangaId, OfflineKeepRule.off, 3);
    for (final c in await db.downloadedChaptersForManga(mangaId)) {
      await deleteChapterFromDevice(ref, c.id);
    }
    ref.invalidate(mangaKeepRuleProvider(mangaId));
    ref.invalidate(mangaDownloadedCountProvider(mangaId));
  }
}
