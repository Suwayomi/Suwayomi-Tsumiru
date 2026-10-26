// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/app_sizes.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../widgets/emoticons.dart';
import '../../../widgets/selection_action_bar.dart';
import '../../../widgets/server_image.dart';
import '../../account/data/account_providers.dart';
import '../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart';
import '../data/account_storage_recovery_state.dart';
import '../data/offline_database.dart';
import '../data/offline_download_providers.dart';
import '../data/offline_dto_mappers.dart';
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
    final series =
        ref.watch(offlineSeriesProvider).value ?? const <OfflineSeriesEntry>[];
    final totalBytes = ref.watch(offlineUsageBytesProvider).value ?? 0;
    final selection = useState<Set<int>>(const {});
    final liveIds = series.map((s) => s.manga.id).toSet();
    final selectedIds = selection.value.intersection(liveIds);
    final selecting = selectedIds.isNotEmpty;
    final selectionFocus = useFocusNode();
    usePruneSelection(selection, liveIds, context);
    useEffect(() {
      if (selecting) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) selectionFocus.requestFocus();
        });
      }
      return null;
    }, [selecting]);
    final desktop = context.usesDesktopShell;
    final activeSeriesId = useState<int?>(null);
    final activeSeries = series.isEmpty
        ? null
        : series.firstWhere(
            (s) => s.manga.id == activeSeriesId.value,
            orElse: () => series.first,
          );

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
        series.where((s) => selectedIds.contains(s.manga.id)).toList();

    final selectionBar = SelectionActionBar(
      leading: [
        IconButton(
          tooltip: context.l10n.cancel,
          icon: const Icon(FluentIcons.dismiss_24_regular),
          onPressed: clear,
        ),
        Text('${selectedIds.length}', style: context.textTheme.titleMedium),
      ],
      actions: [
        IconButton(
          tooltip: context.l10n.manageDownloadsChangeRule,
          icon: const Icon(FluentIcons.options_24_regular),
          onPressed: !canDownload
              ? null
              : () => _bulkChangeRule(context, ref, selectedRows(), clear),
        ),
        IconButton(
          tooltip: context.l10n.manageDownloadsStopKeep,
          icon: const Icon(FluentIcons.bookmark_off_24_regular),
          onPressed: () =>
              _bulkStopKeep(context, ref, selectedIds.toList(), clear),
        ),
        IconButton(
          tooltip: context.l10n.manageDownloadsStopDelete,
          icon: const Icon(FluentIcons.delete_24_regular),
          onPressed: () =>
              _bulkStopDelete(context, ref, selectedIds.toList(), clear),
        ),
      ],
    );
    final content = Stack(
      children: [
        Column(
          children: [
            if (desktop && selecting)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: context.l10n.cancel,
                      icon: const Icon(Icons.close),
                      onPressed: clear,
                    ),
                    Text(
                      context.l10n.numSelected(selectedIds.length),
                      style: context.textTheme.titleSmall,
                    ),
                    IconButton(
                      tooltip: context.l10n.selectAll,
                      icon: const Icon(Icons.select_all),
                      onPressed: () => selection.value = series
                          .map((s) => s.manga.id)
                          .toSet(),
                    ),
                    TextButton.icon(
                      icon: const Icon(FluentIcons.options_24_regular),
                      label: Text(context.l10n.manageDownloadsChangeRule),
                      onPressed: !canDownload
                          ? null
                          : () => _bulkChangeRule(
                              context,
                              ref,
                              selectedRows(),
                              clear,
                            ),
                    ),
                    TextButton.icon(
                      icon: const Icon(FluentIcons.bookmark_off_24_regular),
                      label: Text(context.l10n.manageDownloadsStopKeep),
                      onPressed: () => _bulkStopKeep(
                        context,
                        ref,
                        selectedIds.toList(),
                        clear,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(FluentIcons.delete_24_regular),
                      style: TextButton.styleFrom(
                        foregroundColor: context.theme.colorScheme.error,
                      ),
                      label: Text(context.l10n.manageDownloadsStopDelete),
                      onPressed: () => _bulkStopDelete(
                        context,
                        ref,
                        selectedIds.toList(),
                        clear,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: series.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const DownloadStallBanner(),
                        if (desktop && !selecting)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                            child: Row(
                              children: [
                                Text(
                                  context.l10n.offlineStorageUsage,
                                  style: context.textTheme.titleMedium,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  formatBytes(totalBytes),
                                  style: TextStyle(
                                    color: context
                                        .theme
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (!desktop)
                          ListTile(
                            dense: true,
                            leading: const Icon(FluentIcons.storage_24_regular),
                            title: Text(context.l10n.offlineStorageUsage),
                            trailing: Text(formatBytes(totalBytes)),
                          ),
                        if (!desktop) const Divider(height: 1),
                      ],
                    );
                  }
                  final s = series[index - 1];
                  final selected = selectedIds.contains(s.manga.id);
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
                  if (desktop) {
                    return _OfflineDesktopRow(
                      entry: s,
                      selected: selecting
                          ? selected
                          : s.manga.id == activeSeries?.manga.id,
                      selecting: selecting,
                      ruleLabel: _ruleLabel(context, s.manga),
                      filesLine:
                          '${context.l10n.nChapters(s.downloaded)} · ${formatBytes(s.bytes)}',
                      onTap: selecting
                          ? () => toggle(s.manga.id)
                          : () => activeSeriesId.value = s.manga.id,
                      onSelect: () => toggle(s.manga.id),
                      onMenu: (point) => _openSeriesMenu(
                        context,
                        ref,
                        s.manga,
                        point,
                        () => toggle(s.manga.id),
                      ),
                    );
                  }
                  return ListTile(
                    selected: selected,
                    isThreeLine: true,
                    leading: SizedBox(
                      width: 40,
                      height: 56,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: ServerImage(
                          imageUrl: s.manga.displayCoverUrl,
                          fallbackImageUrl: s.manga.thumbnailUrl,
                          coverVersion: s.manga.coverVersion,
                          fallbackCoverVersion: s.manga.thumbnailUrlLastFetched,
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
                        Text(
                          filesLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                                thumbnailUrl: s.manga.displayCoverUrl,
                                fallbackThumbnailUrl: s.manga.thumbnailUrl,
                                coverVersion: s.manga.coverVersion,
                                fallbackCoverVersion:
                                    s.manga.thumbnailUrlLastFetched,
                              ),
                            ),
                          ),
                    onLongPress: () => toggle(s.manga.id),
                  );
                },
              ),
            ),
          ],
        ),
        if (selecting && !desktop)
          Positioned(left: 0, right: 0, bottom: 0, child: selectionBar),
      ],
    );
    final body = desktop
        ? LayoutBuilder(
            builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: (constraints.maxWidth * 0.4).clamp(0, 400),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: content,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      _OfflineSeriesPaneHeader(
                        entry: activeSeries!,
                        ruleLabel: _ruleLabel(context, activeSeries.manga),
                        onMenu: (point) => _openSeriesMenu(
                          context,
                          ref,
                          activeSeries.manga,
                          point,
                          () => toggle(activeSeries.manga.id),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: OfflineSeriesChaptersBody(
                          key: ValueKey(activeSeries.manga.id),
                          mangaId: activeSeries.manga.id,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        : content;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) clear();
      },
      child: CallbackShortcuts(
        bindings: selecting
            ? {const SingleActivator(LogicalKeyboardKey.escape): clear}
            : const {},
        child: Focus(focusNode: selectionFocus, child: body),
      ),
    );
  }

  Future<void> _openSeriesMenu(
    BuildContext context,
    WidgetRef ref,
    OfflineManga manga,
    Offset point,
    VoidCallback onSelect,
  ) async {
    final canDownload = ref
        .read(settledAccountAccessProvider)
        .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    PopupMenuItem<String> rule(String value, String label, bool checked) =>
        PopupMenuItem(
          value: value,
          enabled: canDownload,
          child: Row(
            children: [
              Expanded(child: Text(label)),
              if (checked)
                const Icon(FluentIcons.checkmark_24_regular, size: 18),
            ],
          ),
        );
    final picked = await showMenu<String>(
      context: context,
      position: menuAnchorForPoint(context, point),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      popUpAnimationStyle: context.motionStyle,
      items: [
        PopupMenuItem(
          enabled: false,
          height: 32,
          child: Text(
            context.l10n.keepOnThisDevice,
            style: context.textTheme.labelSmall,
          ),
        ),
        for (final n in _bufferSizes)
          rule(
            '$n',
            context.l10n.keepOfflineNextUnread(n),
            manga.keepRule == OfflineKeepRule.nUnread &&
                manga.keepUnreadCount == n,
          ),
        rule(
          'unread',
          context.l10n.keepOfflineAllUnread,
          manga.keepRule == OfflineKeepRule.allUnread,
        ),
        rule(
          'all',
          context.l10n.keepOfflineAll,
          manga.keepRule == OfflineKeepRule.all,
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'view',
          child: ChapterMenuRow(
            icon: FluentIcons.book_open_24_regular,
            label: context.l10n.viewManga,
          ),
        ),
        PopupMenuItem(
          value: 'select',
          child: ChapterMenuRow(
            icon: Icons.check_box_outlined,
            label: context.l10n.select,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'stop',
          child: ChapterMenuRow(
            icon: FluentIcons.bookmark_off_24_regular,
            label: context.l10n.manageDownloadsStopKeep,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                FluentIcons.delete_24_regular,
                size: 20,
                color: context.theme.colorScheme.error,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  context.l10n.manageDownloadsStopDelete,
                  style: TextStyle(color: context.theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (!context.mounted || picked == null) return;
    switch (picked) {
      case 'view':
        MangaRoute(mangaId: manga.id).push(context);
      case 'select':
        onSelect();
      case 'stop':
        await detachKeepRule(ref, manga.id);
      case 'delete':
        if (await _confirm(
          context,
          context.l10n.manageDownloadsDeleteConfirm(1),
        )) {
          await removeKeepRuleAndDelete(ref, manga.id);
        }
      case 'unread':
        await confirmAndChangeKeepRule(
          ref,
          manga.id,
          OfflineKeepRule.allUnread,
          manga.keepUnreadCount,
        );
      case 'all':
        await confirmAndChangeKeepRule(
          ref,
          manga.id,
          OfflineKeepRule.all,
          manga.keepUnreadCount,
        );
      default:
        await confirmAndChangeKeepRule(
          ref,
          manga.id,
          OfflineKeepRule.nUnread,
          int.parse(picked),
        );
    }
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

class _OfflineDesktopRow extends HookWidget {
  const _OfflineDesktopRow({
    required this.entry,
    required this.selected,
    required this.selecting,
    required this.ruleLabel,
    required this.filesLine,
    required this.onTap,
    required this.onSelect,
    required this.onMenu,
  });

  final OfflineSeriesEntry entry;
  final bool selected;
  final bool selecting;
  final String ruleLabel;
  final String filesLine;
  final VoidCallback onTap;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final pointer = useRef(Offset.zero);
    final colors = context.theme.colorScheme;
    return GestureDetector(
      onSecondaryTapDown: (event) => onMenu(event.globalPosition),
      child: Material(
        color: selected
            ? colors.secondaryContainer
            : colors.surface.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onSelect,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                if (selecting)
                  Checkbox(value: selected, onChanged: (_) => onSelect()),
                SizedBox(
                  width: 36,
                  height: 50,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: ServerImage(
                      imageUrl: entry.manga.displayCoverUrl,
                      fallbackImageUrl: entry.manga.thumbnailUrl,
                      coverVersion: entry.manga.coverVersion,
                      fallbackCoverVersion:
                          entry.manga.thumbnailUrlLastFetched,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.manga.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleSmall,
                      ),
                      Text(
                        filesLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        ruleLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Listener(
                  onPointerDown: (event) => pointer.value = event.position,
                  child: IconButton(
                    tooltip: context.l10n.manageDownloadsChangeRule,
                    icon: const Icon(FluentIcons.options_24_regular, size: 20),
                    onPressed: () => onMenu(pointer.value),
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

class _OfflineSeriesPaneHeader extends HookWidget {
  const _OfflineSeriesPaneHeader({
    required this.entry,
    required this.ruleLabel,
    required this.onMenu,
  });

  final OfflineSeriesEntry entry;
  final String ruleLabel;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final pointer = useRef(Offset.zero);
    final actions = <Widget>[
      Listener(
        onPointerDown: (event) => pointer.value = event.position,
        child: ActionChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ruleLabel),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more, size: 16),
            ],
          ),
          onPressed: () => onMenu(pointer.value),
        ),
      ),
      TextButton.icon(
        onPressed: () => MangaRoute(mangaId: entry.manga.id).push(context),
        icon: const Icon(FluentIcons.book_open_24_regular, size: 18),
        label: Text(context.l10n.viewManga),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: ServerImage(
                    imageUrl: entry.manga.displayCoverUrl,
                    fallbackImageUrl: entry.manga.thumbnailUrl,
                    coverVersion: entry.manga.coverVersion,
                    fallbackCoverVersion:
                        entry.manga.thumbnailUrlLastFetched,
                    fit: BoxFit.cover,
                    size: const Size(44, 62),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.manga.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleMedium,
                      ),
                      Text(
                        '${context.l10n.nChapters(entry.downloaded)} · ${formatBytes(entry.bytes)}',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (constraints.maxWidth >= 600) ...[
                  const SizedBox(width: 12),
                  ...actions,
                ],
              ],
            ),
            if (constraints.maxWidth < 600) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
