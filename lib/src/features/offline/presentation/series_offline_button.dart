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
        ref.watch(mangaOfflineProgressProvider(mangaId)).value;
    final downloaded = progress?.downloaded ?? 0;
    final inFlight = progress?.inFlight ?? 0;
    final onDevice = downloaded > 0;
    final downloading = inFlight > 0;
    // Surface the active keep-rule on the button so users can see at a glance
    // why a series keeps re-downloading, without opening the sheet (#74).
    final config = ref.watch(mangaKeepConfigProvider(mangaId)).value;
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
          : _ruleLabel(context, config?.rule, config?.count) ??
              (onDevice
                  ? context.l10n.offlineOnDevice
                  : context.l10n.offlineDownloadAction),
      onPressed: () => _openSheet(context, ref, onDevice),
    );
  }

  /// Label for an active keep-rule, or null when no rule is set (rule off) so
  /// the caller falls back to the generic on-device / download label.
  String? _ruleLabel(BuildContext context, OfflineKeepRule? rule, int? count) =>
      switch (rule) {
        OfflineKeepRule.all => context.l10n.keepOfflineAll,
        OfflineKeepRule.allUnread => context.l10n.keepOfflineAllUnread,
        OfflineKeepRule.nUnread =>
          context.l10n.keepOfflineNextUnread(count ?? 5),
        OfflineKeepRule.off || null => null,
      };

  void _openSheet(BuildContext context, WidgetRef ref, bool onDevice) {
    final config = ref.read(mangaKeepConfigProvider(mangaId)).value ??
        (rule: OfflineKeepRule.off, count: 5);
    final rule = config.rule;
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
            // Rolling forward buffer: keep the next N unread downloaded, topped
            // up as you read. Distinct buffer sizes.
            for (final n in const [5, 10, 25])
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: Text(sheetContext.l10n.keepOfflineNextUnread(n)),
                trailing: (rule == OfflineKeepRule.nUnread && config.count == n)
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () =>
                    _apply(sheetContext, ref, OfflineKeepRule.nUnread, n),
              ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(sheetContext.l10n.keepOfflineAllUnread),
              trailing: rule == OfflineKeepRule.allUnread
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => _apply(
                  sheetContext, ref, OfflineKeepRule.allUnread, config.count),
            ),
            ListTile(
              leading: const Icon(Icons.library_books_outlined),
              title: Text(sheetContext.l10n.keepOfflineAll),
              trailing: rule == OfflineKeepRule.all
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () =>
                  _apply(sheetContext, ref, OfflineKeepRule.all, config.count),
            ),
            if (onDevice || rule != OfflineKeepRule.off) ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded,
                    color: sheetContext.theme.colorScheme.error),
                title: Text(
                  sheetContext.l10n.offlineRemoveSeries,
                  style: TextStyle(
                      color: sheetContext.theme.colorScheme.error),
                ),
                onTap: () => _removeAll(sheetContext, ref),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _apply(BuildContext sheetContext, WidgetRef ref,
      OfflineKeepRule rule, int count) async {
    final messenger = ScaffoldMessenger.of(sheetContext);
    final toast = sheetContext.l10n.offlineDownloadingToast;
    Navigator.of(sheetContext).pop();
    await ref.read(offlineDatabaseProvider).setKeepRule(mangaId, rule, count);
    ref.invalidate(mangaKeepRuleProvider(mangaId));
    ref.invalidate(mangaKeepConfigProvider(mangaId));
    messenger.showSnackBar(SnackBar(content: Text(toast)));
    // The reconcile may pull many chapters; run it in the background and refresh
    // the on-device count when it settles — even on failure, so the badge can't
    // get stuck, and swallow the error (best-effort background work).
    unawaited(reconcileMangaWidget(ref, mangaId)
        .whenComplete(
            () => ref.invalidate(mangaDownloadedCountProvider(mangaId)))
        .catchError((_) {/* best-effort */}));
  }

  Future<void> _removeAll(BuildContext sheetContext, WidgetRef ref) async {
    Navigator.of(sheetContext).pop();
    final db = ref.read(offlineDatabaseProvider);
    await db.setKeepRule(mangaId, OfflineKeepRule.off, 5);
    // Purge every chapter with any on-device footprint — not just the fully
    // downloaded ones — so an in-flight/queued download is cancelled too and
    // can't finish after the user asked to remove everything.
    for (final c in await db.chaptersForManga(mangaId)) {
      if (c.deviceState != OfflineDeviceState.none) {
        await deleteChapterFromDevice(ref, c.id);
      }
    }
    ref.invalidate(mangaKeepRuleProvider(mangaId));
    ref.invalidate(mangaKeepConfigProvider(mangaId));
    ref.invalidate(mangaDownloadedCountProvider(mangaId));
  }
}
