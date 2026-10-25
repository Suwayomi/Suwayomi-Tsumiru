// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/app_sizes.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../widgets/emoticons.dart';
import '../../../widgets/selection_action_bar.dart';
import '../../../widgets/server_image.dart';
import '../../account/data/account_providers.dart';
import '../data/account_storage_recovery_state.dart';
import '../data/offline_database.dart';
import '../data/offline_download_providers.dart';
import '../data/offline_repository.dart';
import '../data/offline_series_entry.dart';
import 'download_stall_banner.dart';
import 'keep_rule_picker.dart';
import 'offline_action_confirmations.dart';
import 'offline_series_chapters_screen.dart';
import 'offline_settings_format.dart';

typedef _SeriesRow = OfflineSeriesEntry;

class OfflineFilesView extends HookConsumerWidget {
  const OfflineFilesView({super.key});

  static const _bufferSizes = [5, 10, 25];

  String _ruleLabel(BuildContext context, OfflineManga m) =>
      switch (m.keepRule) {
        OfflineKeepRule.all => context.l10n.keepOfflineAll,
        OfflineKeepRule.allUnread => context.l10n.keepOfflineAllUnread,
        OfflineKeepRule.nUnread => context.l10n.keepOfflineNextUnread(
          m.keepUnreadCount,
        ),
        OfflineKeepRule.off => context.l10n.offlineManualOnly,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDownload = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    if (ref.watch(accountStorageRecoveryProvider) != null) {
      return Center(
        child: Padding(
          padding: KEdgeInsets.a16.size,
          child: Text(
            context.l10n.offlineRecoveryUnavailable,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
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
                  const DownloadStallBanner(),
                  ListTile(
                    dense: true,
                    leading: const Icon(FluentIcons.storage_24_regular),
                    title: Text(context.l10n.offlineStorageUsage),
                    trailing: Text(formatBytes(totalBytes)),
                  ),
                  const Divider(height: 1),
                ],
              );
            }
            final s = series[index - 1];
            final selected = selection.value.contains(s.manga.id);
            final savedLine = s.inFlight > 0
                ? '${context.l10n.offlineDownloadingCount(s.inFlight)} · ${context.l10n.nChapters(s.downloaded)}'
                : s.downloaded > 0
                ? '${context.l10n.nChapters(s.downloaded)} · ${formatBytes(s.bytes)}'
                : context.l10n.manageDownloadsNothingYet;
            final filesLine = s.failed > 0
                ? [
                    '${context.l10n.offlineChaptersErrorSection}: ${s.failed}',
                    if (s.inFlight > 0 || s.downloaded > 0) savedLine,
                  ].join(' · ')
                : savedLine;
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
              title: Text(
                s.manga.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(filesLine, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                icon: const Icon(FluentIcons.options_24_regular),
                onPressed: () => _openSeriesSheet(context, ref, s.manga),
              ),
              onTap: selecting
                  ? () => toggle(s.manga.id)
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OfflineSeriesChaptersScreen(
                          mangaId: s.manga.id,
                          mangaTitle: s.manga.title,
                          thumbnailUrl: s.manga.thumbnailUrl,
                        ),
                      ),
                    ),
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
                  icon: const Icon(FluentIcons.dismiss_24_regular),
                  onPressed: clear,
                ),
                Text(
                  '${selection.value.length}',
                  style: context.textTheme.titleMedium,
                ),
              ],
              actions: [
                IconButton(
                  tooltip: context.l10n.manageDownloadsChangeRule,
                  icon: const Icon(FluentIcons.options_24_regular),
                  onPressed: !canDownload
                      ? null
                      : () => _bulkChangeRule(
                          context,
                          ref,
                          selectedRows(),
                          clear,
                        ),
                ),
                IconButton(
                  tooltip: context.l10n.manageDownloadsStopKeep,
                  icon: const Icon(FluentIcons.bookmark_off_24_regular),
                  onPressed: () => _bulkStopKeep(
                    context,
                    ref,
                    selection.value.toList(),
                    clear,
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.manageDownloadsStopDelete,
                  icon: const Icon(FluentIcons.delete_24_regular),
                  onPressed: () => _bulkStopDelete(
                    context,
                    ref,
                    selection.value.toList(),
                    clear,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }


  void _openSeriesSheet(
    BuildContext context,
    WidgetRef ref,
    OfflineManga manga,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // The library-update strip shrinks available height; avoid the default 9/16 sheet cap.
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final canDownload = sheetRef
              .watch(settledAccountAccessProvider)
              .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!canDownload)
                    ListTile(
                      subtitle: Text(context.l10n.accountPermissionDenied),
                    ),
                  for (final n in _bufferSizes)
                    ListTile(
                      leading: const Icon(FluentIcons.bookmark_add_24_regular),
                      title: Text(sheetContext.l10n.keepOfflineNextUnread(n)),
                      trailing:
                          (manga.keepRule == OfflineKeepRule.nUnread &&
                              manga.keepUnreadCount == n)
                          ? const Icon(FluentIcons.checkmark_24_regular)
                          : null,
                      onTap: canDownload
                          ? () {
                              Navigator.pop(sheetContext);
                              confirmAndChangeKeepRule(
                                ref,
                                manga.id,
                                OfflineKeepRule.nUnread,
                                n,
                              );
                            }
                          : null,
                    ),
                  ListTile(
                    leading: const Icon(FluentIcons.book_open_24_regular),
                    title: Text(sheetContext.l10n.keepOfflineAllUnread),
                    trailing: manga.keepRule == OfflineKeepRule.allUnread
                        ? const Icon(FluentIcons.checkmark_24_regular)
                        : null,
                    onTap: canDownload
                        ? () {
                            Navigator.pop(sheetContext);
                            confirmAndChangeKeepRule(
                              ref,
                              manga.id,
                              OfflineKeepRule.allUnread,
                              manga.keepUnreadCount,
                            );
                          }
                        : null,
                  ),
                  ListTile(
                    leading: const Icon(FluentIcons.library_24_regular),
                    title: Text(sheetContext.l10n.keepOfflineAll),
                    trailing: manga.keepRule == OfflineKeepRule.all
                        ? const Icon(FluentIcons.checkmark_24_regular)
                        : null,
                    onTap: canDownload
                        ? () {
                            Navigator.pop(sheetContext);
                            confirmAndChangeKeepRule(
                              ref,
                              manga.id,
                              OfflineKeepRule.all,
                              manga.keepUnreadCount,
                            );
                          }
                        : null,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(FluentIcons.bookmark_off_24_regular),
                    title: Text(sheetContext.l10n.manageDownloadsStopKeep),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      detachKeepRule(ref, manga.id);
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      FluentIcons.delete_24_regular,
                      color: sheetContext.theme.colorScheme.error,
                    ),
                    title: Text(
                      sheetContext.l10n.manageDownloadsStopDelete,
                      style: TextStyle(
                        color: sheetContext.theme.colorScheme.error,
                      ),
                    ),
                    onTap: () async {
                      final ok = await _confirm(
                        sheetContext,
                        sheetContext.l10n.manageDownloadsDeleteConfirm(1),
                      );
                      if (!sheetContext.mounted) return;
                      Navigator.pop(sheetContext);
                      if (ok) await removeKeepRuleAndDelete(ref, manga.id);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
      sheetAnimationStyle: context.motionStyle,
    );
  }


  Future<void> _bulkChangeRule(
    BuildContext context,
    WidgetRef ref,
    List<_SeriesRow> rows,
    VoidCallback clear,
  ) async {
    if (rows.isEmpty) return;
    final picked = await _pickRule(context);
    if (picked == null || !context.mounted) return;
    if (picked.remove) {
      return _bulkStopDelete(
        context,
        ref,
        rows.map((r) => r.manga.id).toList(),
        clear,
      );
    }
    if (picked.rule == OfflineKeepRule.off) {
      clear();
      for (final r in rows) {
        await detachKeepRule(ref, r.manga.id);
      }
      return;
    }
    if (!await confirmKeepRuleChanges(
          ref,
          rows.map((r) => r.manga.id),
          picked.rule,
          picked.count,
        ) ||
        !context.mounted) {
      return;
    }
    final growing = rows
        .where((r) => picked.rule.index > r.manga.keepRule.index)
        .length;
    if (growing > 0 &&
        !await _confirm(
          context,
          context.l10n.manageDownloadsGrowConfirm(growing),
        )) {
      return;
    }
    clear();
    for (final r in rows) {
      await changeKeepRule(ref, r.manga.id, picked.rule, picked.count);
    }
  }

  Future<void> _bulkStopKeep(
    BuildContext context,
    WidgetRef ref,
    List<int> ids,
    VoidCallback clear,
  ) async {
    if (ids.isEmpty) return;
    if (!await _confirm(
      context,
      context.l10n.manageDownloadsKeepFilesConfirm(ids.length),
    )) {
      return;
    }
    clear();
    for (final id in ids) {
      await detachKeepRule(ref, id);
    }
  }

  Future<void> _bulkStopDelete(
    BuildContext context,
    WidgetRef ref,
    List<int> ids,
    VoidCallback clear,
  ) async {
    if (ids.isEmpty) return;
    if (!await _confirm(
      context,
      context.l10n.manageDownloadsDeleteConfirm(ids.length),
    )) {
      return;
    }
    clear();
    for (final id in ids) {
      await removeKeepRuleAndDelete(ref, id);
    }
  }

  Future<({OfflineKeepRule rule, int count, bool remove})?> _pickRule(
    BuildContext context,
  ) => pickOfflineKeepRule(context);

  Future<bool> _confirm(BuildContext context, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.l10n.yes),
              ),
            ],
          ),
          animationStyle: context.motionStyle,
        ) ??
        false;
  }
}
