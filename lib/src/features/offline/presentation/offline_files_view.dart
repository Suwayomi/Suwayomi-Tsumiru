// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../widgets/emoticons.dart';
import '../../../widgets/selection_action_bar.dart';
import '../../../widgets/server_image.dart';
import '../data/offline_database.dart';
import '../data/offline_download_providers.dart';
import '../data/offline_repository.dart';
import '../data/offline_series_entry.dart';
import 'keep_rule_picker.dart';
import 'offline_settings_format.dart';

typedef _SeriesRow = OfflineSeriesEntry;

/// The "On device" segment of the Downloads tab — the single surface for
/// on-device downloads: every series with files saved here OR an active
/// keep-rule, showing what's downloaded + its rule, with a per-series rule
/// editor and bulk actions. (Replaces the old separate "Manage downloads" page.)
class OfflineFilesView extends HookConsumerWidget {
  const OfflineFilesView({super.key});

  /// The unread-buffer sizes offered for "Keep N unread" (matches the per-series
  /// offline sheet).
  static const _bufferSizes = [5, 10, 25];

  String _ruleLabel(BuildContext context, OfflineManga m) => switch (m.keepRule) {
        OfflineKeepRule.all => context.l10n.keepOfflineAll,
        OfflineKeepRule.allUnread => context.l10n.keepOfflineAllUnread,
        OfflineKeepRule.nUnread =>
          context.l10n.keepOfflineNextUnread(m.keepUnreadCount),
        OfflineKeepRule.off => context.l10n.offlineManualOnly,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(offlineEnabledProvider)) {
      return Center(child: Text(context.l10n.offlineNotAvailable));
    }
    final series = ref.watch(offlineSeriesProvider).value ?? const [];
    final totalBytes = ref.watch(offlineUsageBytesProvider).value ?? 0;
    final selection = useState<Set<int>>(const {});
    final selecting = selection.value.isNotEmpty;

    void clear() => selection.value = const {};
    void toggle(int id) {
      final next = {...selection.value};
      if (!next.add(id)) next.remove(id);
      selection.value = next;
    }

    if (series.isEmpty) {
      return Emoticons(title: context.l10n.offlineNoFiles);
    }

    List<_SeriesRow> selectedRows() =>
        series.where((s) => selection.value.contains(s.manga.id)).toList();

    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: series.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.sd_storage_outlined),
                    title: Text(context.l10n.offlineStorageUsage),
                    trailing: Text(formatBytes(totalBytes)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      context.l10n.offlineManageHint,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                ],
              );
            }
            final s = series[index - 1];
            final selected = selection.value.contains(s.manga.id);
            final filesLine = s.inFlight > 0
                ? '${context.l10n.offlineDownloadingCount(s.inFlight)} · ${context.l10n.nChapters(s.downloaded)}'
                : s.downloaded > 0
                    ? '${context.l10n.nChapters(s.downloaded)} · ${formatBytes(s.bytes)}'
                    : context.l10n.manageDownloadsNothingYet;
            return ListTile(
              selected: selected,
              isThreeLine: true,
              leading: SizedBox(
                width: 40,
                height: 56,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: ServerImage(
                    imageUrl: s.manga.thumbnailUrl ?? '',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              title:
                  Text(s.manga.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(filesLine,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    _ruleLabel(context, s.manga),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              trailing: IconButton(
                tooltip: context.l10n.manageDownloadsChangeRule,
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => _openSeriesSheet(context, ref, s.manga),
              ),
              onTap: selecting
                  ? () => toggle(s.manga.id)
                  : () => MangaRoute(mangaId: s.manga.id).push(context),
              onLongPress: () => toggle(s.manga.id),
            );
          },
        ),
        if (selecting)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SelectionActionBar(
              leading: [
                IconButton(
                  tooltip: context.l10n.cancel,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: clear,
                ),
                Text('${selection.value.length}',
                    style: context.textTheme.titleMedium),
              ],
              actions: [
                IconButton(
                  tooltip: context.l10n.manageDownloadsChangeRule,
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: () =>
                      _bulkChangeRule(context, ref, selectedRows(), clear),
                ),
                IconButton(
                  tooltip: context.l10n.manageDownloadsStopKeep,
                  icon: const Icon(Icons.bookmark_remove_outlined),
                  onPressed: () => _bulkStopKeep(
                      context, ref, selection.value.toList(), clear),
                ),
                IconButton(
                  tooltip: context.l10n.manageDownloadsStopDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _bulkStopDelete(
                      context, ref, selection.value.toList(), clear),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Single-series action sheet (the row's gear button)
  // ---------------------------------------------------------------------------

  void _openSeriesSheet(
      BuildContext context, WidgetRef ref, OfflineManga manga) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final n in _bufferSizes)
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: Text(sheetContext.l10n.keepOfflineNextUnread(n)),
                trailing: (manga.keepRule == OfflineKeepRule.nUnread &&
                        manga.keepUnreadCount == n)
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  changeKeepRule(ref, manga.id, OfflineKeepRule.nUnread, n);
                },
              ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(sheetContext.l10n.keepOfflineAllUnread),
              trailing: manga.keepRule == OfflineKeepRule.allUnread
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () {
                Navigator.pop(sheetContext);
                changeKeepRule(ref, manga.id, OfflineKeepRule.allUnread,
                    manga.keepUnreadCount);
              },
            ),
            ListTile(
              leading: const Icon(Icons.library_books_outlined),
              title: Text(sheetContext.l10n.keepOfflineAll),
              trailing: manga.keepRule == OfflineKeepRule.all
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () {
                Navigator.pop(sheetContext);
                changeKeepRule(
                    ref, manga.id, OfflineKeepRule.all, manga.keepUnreadCount);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.bookmark_remove_outlined),
              title: Text(sheetContext.l10n.manageDownloadsStopKeep),
              onTap: () {
                Navigator.pop(sheetContext);
                detachKeepRule(ref, manga.id);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: sheetContext.theme.colorScheme.error),
              title: Text(sheetContext.l10n.manageDownloadsStopDelete,
                  style:
                      TextStyle(color: sheetContext.theme.colorScheme.error)),
              onTap: () async {
                final ok = await _confirm(sheetContext,
                    sheetContext.l10n.manageDownloadsDeleteConfirm(1));
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                if (ok) await removeKeepRuleAndDelete(ref, manga.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bulk actions
  // ---------------------------------------------------------------------------

  Future<void> _bulkChangeRule(BuildContext context, WidgetRef ref,
      List<_SeriesRow> rows, VoidCallback clear) async {
    if (rows.isEmpty) return;
    final picked = await _pickRule(context);
    if (picked == null || !context.mounted) return;
    final growing =
        rows.where((r) => picked.rule.index > r.manga.keepRule.index).length;
    if (growing > 0 &&
        !await _confirm(
            context, context.l10n.manageDownloadsGrowConfirm(growing))) {
      return;
    }
    clear();
    for (final r in rows) {
      await changeKeepRule(ref, r.manga.id, picked.rule, picked.count);
    }
  }

  Future<void> _bulkStopKeep(BuildContext context, WidgetRef ref,
      List<int> ids, VoidCallback clear) async {
    if (ids.isEmpty) return;
    if (!await _confirm(
        context, context.l10n.manageDownloadsKeepFilesConfirm(ids.length))) {
      return;
    }
    clear();
    for (final id in ids) {
      await detachKeepRule(ref, id);
    }
  }

  Future<void> _bulkStopDelete(BuildContext context, WidgetRef ref,
      List<int> ids, VoidCallback clear) async {
    if (ids.isEmpty) return;
    if (!await _confirm(
        context, context.l10n.manageDownloadsDeleteConfirm(ids.length))) {
      return;
    }
    clear();
    for (final id in ids) {
      await removeKeepRuleAndDelete(ref, id);
    }
  }

  Future<({OfflineKeepRule rule, int count})?> _pickRule(
          BuildContext context) =>
      pickOfflineKeepRule(context);

  Future<bool> _confirm(BuildContext context, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text(message),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(ctx.l10n.cancel)),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(ctx.l10n.yes)),
            ],
          ),
        ) ??
        false;
  }
}
